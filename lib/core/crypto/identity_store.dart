import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'join_identity.dart';
import 'recovery_phrase.dart';

/// Guarda la identidad criptográfica del usuario y publica su parte pública.
///
/// La entropía de la que sale la clave privada vive en el llavero del sistema
/// (Keystore en Android, Keychain en iOS) y **nunca** se envía a ningún sitio.
/// Lo único que sube a Supabase es la clave pública.
///
/// La entropía se guarda por usuario: en un móvil compartido, dos cuentas
/// tienen identidades distintas y ninguna puede leer los chats de la otra.
class IdentityStore {
  IdentityStore({FlutterSecureStorage? storage, SupabaseClient? client})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                // La clave se guarda cifrada con el Keystore del dispositivo.
                encryptedSharedPreferences: true,
                // Sin `resetOnError`: si la lectura falla, el paquete puede
                // borrar lo guardado. Para un token de sesión daría igual;
                // aquí significaría tirar la identidad del usuario —y con ella
                // todo su historial— sin avisar. Mejor que falle a la vista y
                // se pueda restaurar con la frase.
                resetOnError: false,
              ),
            ),
        _supabase = client ?? Supabase.instance.client;

  final FlutterSecureStorage _storage;
  final SupabaseClient _supabase;

  JoinIdentity? _cached;
  String? _cachedFor;

  static String _slotFor(String userId) => 'join_identity_entropy_$userId';

  /// La identidad de [userId], creándola la primera vez.
  ///
  /// Es idempotente y cachea en memoria: se llama en cada apertura de chat.
  Future<JoinIdentity> identityFor(String userId) async {
    if (_cached != null && _cachedFor == userId) return _cached!;

    final phrase = await _phraseFor(userId, createIfMissing: true);
    final identity = await JoinIdentity.fromPhrase(phrase!);

    _cached = identity;
    _cachedFor = userId;
    return identity;
  }

  /// Las 12 palabras de [userId], para enseñárselas cuando las pida.
  ///
  /// Devuelve `null` si todavía no hay identidad: no se crea una sólo por
  /// consultarla.
  Future<String?> recoveryPhraseFor(String userId) =>
      _phraseFor(userId, createIfMissing: false);

  /// Sustituye la identidad local por la que describe [phrase].
  ///
  /// Es lo que se ejecuta al restaurar en un móvil nuevo. Lanza
  /// [FormatException] si la frase no supera el checksum, antes de tocar nada.
  Future<JoinIdentity> restoreFrom({
    required String userId,
    required String phrase,
  }) async {
    final normalized = RecoveryPhrase.normalize(phrase);
    RecoveryPhrase.toEntropy(normalized); // valida o lanza

    await _storage.write(key: _slotFor(userId), value: normalized);
    _cached = null;
    _cachedFor = null;

    final identity = await identityFor(userId);
    await publishPublicKey(userId: userId, identity: identity);
    return identity;
  }

  /// Deja la clave pública de [userId] publicada y al día.
  ///
  /// Se llama al arrancar la sesión. Si el usuario reinstaló sin la frase,
  /// aquí es donde su clave nueva sustituye a la vieja; a partir de ese
  /// momento los chats rotan de época y vuelve a poder leer lo nuevo (lo
  /// anterior a la reinstalación se queda ilegible, que es el trato).
  Future<void> publishPublicKey({
    required String userId,
    JoinIdentity? identity,
  }) async {
    final mine = identity ?? await identityFor(userId);

    try {
      final row = await _supabase
          .from('user_keys')
          .select('public_key')
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) {
        await _supabase.from('user_keys').insert({
          'user_id': userId,
          'public_key': mine.publicKeyBase64,
        });
      } else if (row['public_key'] != mine.publicKeyBase64) {
        await _supabase
            .from('user_keys')
            .update({
              'public_key': mine.publicKeyBase64,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('user_id', userId);
      }
    } catch (e) {
      // Sin conexión no se puede publicar, pero la identidad local ya está
      // creada y el chat seguirá funcionando en cuanto vuelva la red.
      debugPrint('No se pudo publicar la clave pública: $e');
    }
  }

  /// Las claves públicas de varios usuarios, en Base64 y por id.
  ///
  /// Quien no aparezca es que aún no ha abierto la app desde que existe el
  /// cifrado: no se le puede envolver la clave todavía.
  Future<Map<String, Uint8List>> publicKeysOf(List<String> userIds) async {
    if (userIds.isEmpty) return {};

    final rows = await _supabase
        .from('user_keys')
        .select('user_id, public_key')
        .inFilter('user_id', userIds);

    final result = <String, Uint8List>{};
    for (final row in rows) {
      try {
        final bytes = base64Decode(row['public_key'] as String);
        // Una pública de X25519 mide 32 bytes; cualquier otra cosa es un
        // dato corrupto que no debe llegar al cifrado.
        if (bytes.length == 32) {
          result[row['user_id'] as String] = Uint8List.fromList(bytes);
        }
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  /// Olvida lo cacheado en memoria. Se llama al cerrar sesión; la entropía
  /// sigue en el llavero para cuando el mismo usuario vuelva a entrar.
  void forgetCache() {
    _cached = null;
    _cachedFor = null;
  }

  Future<String?> _phraseFor(
    String userId, {
    required bool createIfMissing,
  }) async {
    if (userId.isEmpty) {
      throw const CryptoException('No hay sesión para resolver la identidad.');
    }

    final slot = _slotFor(userId);
    final stored = await _storage.read(key: slot);
    if (stored != null && RecoveryPhrase.isValid(stored)) return stored;

    if (stored != null) {
      // Había algo que no es una frase válida. Sobrescribirlo dejaría
      // ilegibles los mensajes de su dueño legítimo, así que se avisa en vez
      // de continuar en silencio.
      debugPrint(
        'La identidad guardada de $userId no es válida; se genera una nueva.',
      );
    }
    if (!createIfMissing) return null;

    final phrase = RecoveryPhrase.fromEntropy(RecoveryPhrase.newEntropy());
    await _storage.write(key: slot, value: phrase);
    return phrase;
  }
}
