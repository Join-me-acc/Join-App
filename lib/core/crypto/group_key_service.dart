import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'group_cipher.dart';
import 'identity_store.dart';
import 'join_identity.dart';

/// La época vigente de una conversación y su clave.
class GroupSession {
  const GroupSession({required this.epoch, required this.key});

  final int epoch;
  final Uint8List key;
}

/// Reparte y resuelve las claves de grupo.
///
/// Una conversación no tiene una clave, sino una por **época**. Se abre una
/// época nueva cuando cambia quién puede leer: entra alguien, sale alguien, o
/// un miembro reinstala y estrena clave. Así:
///
/// · quien entra hoy no puede leer lo de ayer —no tiene la clave de esa época—
/// · quien salió ayer no puede leer lo de hoy, aunque conserve la clave vieja
///
/// La rotación la dispara el cliente, porque el servidor no tiene con qué
/// envolver claves. Cualquier miembro que abra el chat y note el cambio la
/// hace; si dos coinciden, la restricción de unicidad de la tabla decide y el
/// perdedor relee.
class GroupKeyService {
  GroupKeyService({
    required IdentityStore identityStore,
    SupabaseClient? client,
  })  : _identities = identityStore,
        _supabase = client ?? Supabase.instance.client;

  final IdentityStore _identities;
  final SupabaseClient _supabase;

  /// Claves ya abiertas, por conversación y época. Sólo en memoria: al cerrar
  /// la app se vuelven a pedir y a desenvolver.
  final Map<String, Map<int, Uint8List>> _keys = {};

  /// Última comprobación de membresía, para no recalcularla en cada mensaje.
  final Map<String, DateTime> _lastMembershipCheck = {};
  final Map<String, GroupSession> _sessions = {};

  static const _membershipTtl = Duration(seconds: 30);

  String get _userId {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw const CryptoException('No hay sesión activa.');
    return id;
  }

  /// La sesión con la que cifrar lo que se envíe ahora.
  Future<GroupSession> currentSession(ConversationRef conversation) async {
    final cacheKey = conversation.toString();
    final latest = await _latestEpochRow(conversation);

    final cached = _sessions[cacheKey];
    final checkedAt = _lastMembershipCheck[cacheKey];
    final membershipIsFresh = checkedAt != null &&
        DateTime.now().difference(checkedAt) < _membershipTtl;

    // Nada ha cambiado desde hace un momento: se reutiliza.
    if (cached != null &&
        latest != null &&
        cached.epoch == latest['epoch'] as int &&
        membershipIsFresh) {
      return cached;
    }

    final roster = await _rosterOf(conversation);
    final hash = _hashOf(roster);

    if (latest != null && latest['members_hash'] == hash) {
      final epoch = latest['epoch'] as int;
      final key = await keyForEpoch(conversation, epoch);
      if (key != null) {
        final session = GroupSession(epoch: epoch, key: key);
        _sessions[cacheKey] = session;
        _lastMembershipCheck[cacheKey] = DateTime.now();
        return session;
      }
      // El reparto de esa época no llegó a este usuario aunque le tocaba.
      // Se abre una nueva en vez de dejarlo sin poder escribir.
      debugPrint('Sin clave propia en la época $epoch de $conversation; se rota.');
    }

    final session = await _openNewEpoch(
      conversation: conversation,
      roster: roster,
      hash: hash,
      previousEpoch: latest == null ? 0 : latest['epoch'] as int,
    );
    _sessions[cacheKey] = session;
    _lastMembershipCheck[cacheKey] = DateTime.now();
    return session;
  }

  /// La clave de una época concreta, o `null` si este usuario no la tiene.
  ///
  /// `null` es la respuesta normal para los mensajes anteriores a su entrada
  /// al grupo, no un error.
  Future<Uint8List?> keyForEpoch(ConversationRef conversation, int epoch) async {
    final cacheKey = conversation.toString();
    final cachedKey = _keys[cacheKey]?[epoch];
    if (cachedKey != null) return cachedKey;

    try {
      final row = await _supabase
          .from('epoch_keys')
          .select('wrapped_key, conversation_epochs!inner(scope, scope_id, epoch)')
          .eq('user_id', _userId)
          .eq('conversation_epochs.scope', conversation.scope)
          .eq('conversation_epochs.scope_id', conversation.id)
          .eq('conversation_epochs.epoch', epoch)
          .maybeSingle();

      if (row == null) return null;

      final identity = await _identities.identityFor(_userId);
      final key = await identity.unwrapGroupKey(row['wrapped_key'] as String);

      (_keys[cacheKey] ??= {})[epoch] = key;
      return key;
    } on CryptoException catch (e) {
      // El envoltorio existe pero no abre: la clave se repartió para una
      // identidad anterior de este usuario. Se trata como "no la tengo".
      debugPrint('No se pudo abrir la clave de la época $epoch: $e');
      return null;
    } catch (e) {
      debugPrint('Error al recuperar la clave de la época $epoch: $e');
      return null;
    }
  }

  /// El resolutor que [GroupCipher] usa para descifrar cada mensaje.
  GroupKeyResolver resolverFor(ConversationRef conversation) =>
      (epoch) => keyForEpoch(conversation, epoch);

  /// Olvida todo lo cacheado. Al cerrar sesión.
  void clear() {
    _keys.clear();
    _sessions.clear();
    _lastMembershipCheck.clear();
  }

  /// Fuerza a recomprobar la membresía en la próxima consulta. Se llama tras
  /// aceptar a alguien o al salirse un miembro.
  void invalidate(ConversationRef conversation) {
    final cacheKey = conversation.toString();
    _sessions.remove(cacheKey);
    _lastMembershipCheck.remove(cacheKey);
  }

  // ── Interno ───────────────────────────────────────────────

  Future<Map<String, dynamic>?> _latestEpochRow(
    ConversationRef conversation,
  ) async {
    try {
      return await _supabase
          .from('conversation_epochs')
          .select('id, epoch, members_hash')
          .eq('scope', conversation.scope)
          .eq('scope_id', conversation.id)
          .order('epoch', ascending: false)
          .limit(1)
          .maybeSingle();
    } catch (e) {
      debugPrint('Error al leer la última época de $conversation: $e');
      return null;
    }
  }

  /// Los miembros que hoy pueden leer, con su clave pública.
  ///
  /// Quien todavía no ha publicado clave queda fuera: no hay con qué
  /// envolverle nada. Entrará en la siguiente rotación, que se disparará sola
  /// en cuanto publique, porque la huella habrá cambiado.
  Future<Map<String, Uint8List>> _rosterOf(ConversationRef conversation) async {
    final memberIds = conversation.scope == 'clan'
        ? await _clanMemberIds(conversation.id)
        : await _activityMemberIds(conversation.id);

    return _identities.publicKeysOf(memberIds.toList());
  }

  Future<Set<String>> _clanMemberIds(String clanId) async {
    final rows = await _supabase
        .from('clan_members')
        .select('user_id')
        .eq('clan_id', clanId);
    return {
      for (final row in rows)
        if (row['user_id'] != null) row['user_id'] as String,
    };
  }

  Future<Set<String>> _activityMemberIds(String activityId) async {
    final activity = await _supabase
        .from('activities')
        .select('organizer_id')
        .eq('id', activityId)
        .maybeSingle();

    final participants = await _supabase
        .from('activity_participants')
        .select('user_id')
        .eq('activity_id', activityId);

    return {
      if (activity?['organizer_id'] != null) activity!['organizer_id'] as String,
      for (final row in participants)
        if (row['user_id'] != null) row['user_id'] as String,
    };
  }

  /// Huella del conjunto (miembro, clave pública).
  ///
  /// Incluir la clave y no sólo el id es lo que hace que reinstalar dispare
  /// una rotación: el usuario sigue siendo el mismo, pero su clave ya no.
  static String _hashOf(Map<String, Uint8List> roster) {
    final entries = roster.entries
        .map((e) => '${e.key}:${base64Encode(e.value)}')
        .toList()
      ..sort();

    final digest = Sha256().toSync().hashSync(utf8.encode(entries.join('|')));
    return base64Encode(digest.bytes);
  }

  Future<GroupSession> _openNewEpoch({
    required ConversationRef conversation,
    required Map<String, Uint8List> roster,
    required String hash,
    required int previousEpoch,
  }) async {
    if (!roster.containsKey(_userId)) {
      throw const CryptoException(
        'Tu clave de cifrado aún no está publicada. Vuelve a intentarlo en un momento.',
      );
    }

    final epoch = previousEpoch + 1;
    final key = GroupCipher.newGroupKey();

    final Map<String, dynamic> created;
    try {
      created = await _supabase
          .from('conversation_epochs')
          .insert({
            'scope': conversation.scope,
            'scope_id': conversation.id,
            'epoch': epoch,
            'members_hash': hash,
            'member_ids': roster.keys.toList(),
            'created_by': _userId,
          })
          .select('id, epoch')
          .single();
    } on PostgrestException catch (e) {
      // 23505 = unicidad: otro miembro abrió esta misma época a la vez. Su
      // clave es tan buena como la nuestra, así que se usa la suya.
      if (e.code == '23505') {
        final theirs = await keyForEpoch(conversation, epoch);
        if (theirs != null) return GroupSession(epoch: epoch, key: theirs);
      }
      rethrow;
    }

    final epochId = created['id'] as String;
    final wrapped = <Map<String, dynamic>>[];
    for (final entry in roster.entries) {
      wrapped.add({
        'epoch_id': epochId,
        'user_id': entry.key,
        'wrapped_key': await JoinIdentity.wrapGroupKey(
          groupKey: key,
          recipientPublicKey: entry.value,
        ),
      });
    }

    await _supabase.from('epoch_keys').insert(wrapped);

    (_keys[conversation.toString()] ??= {})[epoch] = key;
    return GroupSession(epoch: epoch, key: key);
  }
}
