import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/storage_paths.dart';
import 'group_cipher.dart';
import 'group_key_service.dart';
import 'identity_store.dart';
import 'join_identity.dart';

export 'group_cipher.dart' show ConversationRef, DecryptedText, DecryptionStatus;

/// Punto único de entrada al cifrado de los chats.
///
/// Las pantallas y los repositorios no hablan con las claves: piden cifrar o
/// descifrar y esta clase se ocupa de qué época toca, de repartir claves y de
/// subir o bajar los adjuntos.
class ChatCrypto {
  ChatCrypto._();

  static final ChatCrypto instance = ChatCrypto._();

  final IdentityStore _identities = IdentityStore();
  late final GroupKeyService _groupKeys =
      GroupKeyService(identityStore: _identities);

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Adjuntos ya descargados y abiertos, por ruta. Evita bajar y descifrar la
  /// misma foto en cada reconstrucción de la lista.
  final LinkedHashMap<String, Uint8List> _imageCache = LinkedHashMap();
  static const int _imageCacheLimit = 40;

  IdentityStore get identities => _identities;

  // ── Ciclo de sesión ───────────────────────────────────────

  /// Prepara la identidad del usuario y publica su clave pública.
  ///
  /// Es seguro llamarlo en cada arranque: sólo escribe si falta o cambió.
  Future<void> onSignIn(String userId) async {
    try {
      await _identities.publishPublicKey(userId: userId);
    } catch (e) {
      debugPrint('No se pudo preparar el cifrado para $userId: $e');
    }
  }

  void onSignOut() {
    _identities.forgetCache();
    _groupKeys.clear();
    _imageCache.clear();
  }

  /// Fuerza a recomprobar quién puede leer. Tras aceptar a alguien en una
  /// actividad o al entrar o salir de un clan.
  void membershipChanged(ConversationRef conversation) =>
      _groupKeys.invalidate(conversation);

  // ── Texto ─────────────────────────────────────────────────

  /// Cifra un mensaje con la clave vigente de [conversation].
  Future<String> encryptText(ConversationRef conversation, String clearText) async {
    if (clearText.isEmpty) return '';
    final session = await _groupKeys.currentSession(conversation);
    return GroupCipher.encryptText(
      clearText: clearText,
      groupKey: session.key,
      epoch: session.epoch,
      conversation: conversation,
    );
  }

  /// Descifra un mensaje. Nunca lanza: devuelve el motivo si no se puede.
  Future<DecryptedText> decryptText(
    ConversationRef conversation,
    String stored,
  ) =>
      GroupCipher.decryptText(
        stored: stored,
        resolveKey: _groupKeys.resolverFor(conversation),
        conversation: conversation,
      );

  /// Descifra una tanda de mensajes conservando el orden.
  Future<List<DecryptedText>> decryptAll(
    ConversationRef conversation,
    List<String> stored,
  ) async {
    final resolver = _groupKeys.resolverFor(conversation);
    return [
      for (final one in stored)
        await GroupCipher.decryptText(
          stored: one,
          resolveKey: resolver,
          conversation: conversation,
        ),
    ];
  }

  /// Lo que se muestra cuando un mensaje no se puede leer.
  ///
  /// Decirlo con estas palabras importa: "no tienes la clave" es el
  /// funcionamiento normal para quien acaba de entrar al grupo, y no debe
  /// parecer un error de la app.
  static String placeholderFor(DecryptionStatus status) {
    switch (status) {
      case DecryptionStatus.noKey:
        return '🔒 Mensaje anterior a tu entrada al grupo';
      case DecryptionStatus.corrupt:
        return '⚠️ Este mensaje no se pudo descifrar';
      case DecryptionStatus.ok:
      case DecryptionStatus.legacy:
        return '';
    }
  }

  /// El texto que la interfaz debe pintar, ya resuelto.
  static String displayText(DecryptedText decrypted) =>
      decrypted.isReadable ? decrypted.text : placeholderFor(decrypted.status);

  // ── Imágenes ──────────────────────────────────────────────

  /// Cifra [image] y la sube al bucket privado.
  ///
  /// Devuelve la **ruta** dentro del bucket, no una URL: sin cifrar, una URL
  /// pública dejaría la foto al alcance de cualquiera que la tuviera.
  Future<String> uploadImage({
    required ConversationRef conversation,
    required File image,
  }) async {
    StoragePaths.ensureWithinLimit(image, StoragePaths.imageMaxBytes);
    // Se valida la extensión aunque el blob suba como datos opacos: es lo que
    // impide colar un ejecutable disfrazado de foto.
    StoragePaths.extensionOf(image.path);

    final session = await _groupKeys.currentSession(conversation);
    final sealed = await GroupCipher.encryptBytes(
      clearBytes: await image.readAsBytes(),
      groupKey: session.key,
      epoch: session.epoch,
      conversation: conversation,
    );

    final userId = _supabase.auth.currentUser?.id ?? '';
    final path = StoragePaths.chatAttachment(
      userId: userId,
      scope: conversation.scope,
      conversationId: conversation.id,
    );

    await _supabase.storage.from(StoragePaths.chatBucket).uploadBinary(
          path,
          sealed,
          fileOptions: const FileOptions(contentType: 'application/octet-stream'),
        );

    return path;
  }

  /// Baja y abre un adjunto. `null` si no se puede mostrar.
  ///
  /// Devolver `null` en vez de lanzar deja que la interfaz pinte una imagen
  /// rota, que es lo correcto para una foto de una época que este usuario no
  /// tiene.
  Future<Uint8List?> imageBytes({
    required ConversationRef conversation,
    required String path,
  }) async {
    final cached = _imageCache[path];
    if (cached != null) return cached;

    try {
      final sealed =
          await _supabase.storage.from(StoragePaths.chatBucket).download(path);

      final epoch = GroupCipher.epochOfBytes(sealed);
      if (epoch == null) return null;

      final key = await _groupKeys.keyForEpoch(conversation, epoch);
      if (key == null) return null;

      final clear = await GroupCipher.decryptBytes(
        blob: sealed,
        groupKey: key,
        conversation: conversation,
      );

      _remember(path, clear);
      return clear;
    } on CryptoException catch (e) {
      debugPrint('No se pudo abrir el adjunto $path: $e');
      return null;
    } catch (e) {
      debugPrint('No se pudo descargar el adjunto $path: $e');
      return null;
    }
  }

  /// `true` si [reference] es un adjunto cifrado y no una URL de las de antes.
  ///
  /// Las imágenes anteriores al cifrado se guardaron como URL pública y siguen
  /// mostrándose igual; las nuevas son rutas dentro del bucket privado.
  static bool isEncryptedAttachment(String reference) =>
      reference.isNotEmpty && !reference.startsWith('http');

  void _remember(String path, Uint8List bytes) {
    if (_imageCache.length >= _imageCacheLimit) {
      _imageCache.remove(_imageCache.keys.first);
    }
    _imageCache[path] = bytes;
  }
}
