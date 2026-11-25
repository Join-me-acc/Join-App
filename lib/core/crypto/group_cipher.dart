import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../services/encryption_service.dart';
import 'join_identity.dart';

/// A qué conversación pertenece un mensaje.
///
/// Va dentro del cifrado como dato autenticado, de modo que un mensaje no se
/// puede mover de un chat a otro ni de una época a otra: al cambiar el
/// contexto, la comprobación de integridad falla y el texto no se abre.
class ConversationRef {
  const ConversationRef.activity(this.id) : scope = 'activity';
  const ConversationRef.clan(this.id) : scope = 'clan';

  final String scope;
  final String id;

  List<int> aadFor(int epoch) => utf8.encode('$scope:$id:$epoch');

  @override
  bool operator ==(Object other) =>
      other is ConversationRef && other.scope == scope && other.id == id;

  @override
  int get hashCode => Object.hash(scope, id);

  @override
  String toString() => '$scope:$id';
}

/// Por qué un texto se muestra como se muestra.
enum DecryptionStatus {
  /// Descifrado con la clave de su época.
  ok,

  /// Descifrado con la clave antigua del binario. Son mensajes anteriores al
  /// cifrado real; se leen para no perder el historial.
  legacy,

  /// El mensaje es de una época que este usuario no tiene: se escribió antes
  /// de que entrara al grupo. No es un error.
  noKey,

  /// El mensaje no se puede abrir con la clave que le corresponde. Aquí sí
  /// hay algo mal: manipulación o corrupción.
  corrupt,
}

/// Un texto ya resuelto, con el motivo de lo que se ve.
class DecryptedText {
  const DecryptedText(this.text, this.status);

  final String text;
  final DecryptionStatus status;

  bool get isReadable =>
      status == DecryptionStatus.ok || status == DecryptionStatus.legacy;
}

/// Devuelve la clave de una época, o `null` si este usuario no la tiene.
typedef GroupKeyResolver = Future<Uint8List?> Function(int epoch);

/// Cifrado de los mensajes y de las imágenes del chat con la clave de grupo.
///
/// Nada aquí sabe de Supabase: recibe la clave ya resuelta. Así el cifrado se
/// puede probar entero sin red y sin base de datos.
class GroupCipher {
  const GroupCipher._();

  static final _aes = AesGcm.with256bits();
  static final _random = Random.secure();

  /// Marca de versión del texto cifrado. Todo lo que no la lleve es anterior
  /// al cifrado real y se trata como histórico.
  static const String textPrefix = 'v2';

  /// Cabecera de una imagen cifrada. Permite reconocer el blob y negarse a
  /// mostrar como imagen algo que no lo es.
  static const List<int> imageMagic = [0x4a, 0x4f, 0x49, 0x4e, 0x49, 0x4d, 0x47, 0x31]; // JOINIMG1

  static const int keyBytes = 32;
  static const int _nonceBytes = 12;
  static const int _macBytes = 16;

  /// Una clave de grupo nueva.
  static Uint8List newGroupKey() => Uint8List.fromList(
        List<int>.generate(keyBytes, (_) => _random.nextInt(256)),
      );

  // ── Texto ─────────────────────────────────────────────────

  /// Cifra [clearText] con la clave de [epoch].
  ///
  /// El texto vacío se deja tal cual: un mensaje que sólo lleva imagen guarda
  /// cadena vacía, y cifrarla sólo añadiría ruido sin ocultar nada.
  static Future<String> encryptText({
    required String clearText,
    required Uint8List groupKey,
    required int epoch,
    required ConversationRef conversation,
  }) async {
    if (clearText.isEmpty) return '';
    _ensureKeyShape(groupKey);

    final box = await _aes.encrypt(
      utf8.encode(clearText),
      secretKey: SecretKey(groupKey),
      nonce: _aes.newNonce(),
      aad: conversation.aadFor(epoch),
    );

    return [
      textPrefix,
      '$epoch',
      base64Encode(box.nonce),
      base64Encode(box.cipherText + box.mac.bytes),
    ].join('.');
  }

  /// Descifra lo que venga: formato nuevo, formato antiguo o texto plano.
  ///
  /// Nunca lanza ni devuelve basura. Un mensaje que no se puede abrir se
  /// informa con su motivo para que la interfaz diga la verdad en vez de
  /// pintar caracteres sueltos.
  static Future<DecryptedText> decryptText({
    required String stored,
    required GroupKeyResolver resolveKey,
    required ConversationRef conversation,
  }) async {
    if (stored.isEmpty) return const DecryptedText('', DecryptionStatus.ok);

    if (!stored.startsWith('$textPrefix.')) {
      // Anterior al cifrado real: la clave estaba en el binario.
      return DecryptedText(
        EncryptionService.decryptText(stored),
        DecryptionStatus.legacy,
      );
    }

    final parts = stored.split('.');
    if (parts.length != 4) {
      return const DecryptedText('', DecryptionStatus.corrupt);
    }

    final epoch = int.tryParse(parts[1]);
    if (epoch == null) return const DecryptedText('', DecryptionStatus.corrupt);

    final List<int> nonce;
    final List<int> payload;
    try {
      nonce = base64Decode(parts[2]);
      payload = base64Decode(parts[3]);
    } on FormatException {
      return const DecryptedText('', DecryptionStatus.corrupt);
    }

    if (nonce.length != _nonceBytes || payload.length <= _macBytes) {
      return const DecryptedText('', DecryptionStatus.corrupt);
    }

    final key = await resolveKey(epoch);
    if (key == null) return const DecryptedText('', DecryptionStatus.noKey);

    try {
      final clear = await _aes.decrypt(
        SecretBox(
          payload.sublist(0, payload.length - _macBytes),
          nonce: nonce,
          mac: Mac(payload.sublist(payload.length - _macBytes)),
        ),
        secretKey: SecretKey(key),
        aad: conversation.aadFor(epoch),
      );
      return DecryptedText(utf8.decode(clear), DecryptionStatus.ok);
    } on SecretBoxAuthenticationError {
      return const DecryptedText('', DecryptionStatus.corrupt);
    } on FormatException {
      // Descifró, pero no era UTF-8: la clave no era la correcta.
      return const DecryptedText('', DecryptionStatus.corrupt);
    }
  }

  // ── Imágenes ──────────────────────────────────────────────

  /// Cifra los bytes de una imagen. El resultado es lo que se sube al bucket,
  /// que a partir de ahora es privado y sólo guarda blobs ilegibles.
  static Future<Uint8List> encryptBytes({
    required Uint8List clearBytes,
    required Uint8List groupKey,
    required int epoch,
    required ConversationRef conversation,
  }) async {
    _ensureKeyShape(groupKey);

    final box = await _aes.encrypt(
      clearBytes,
      secretKey: SecretKey(groupKey),
      nonce: _aes.newNonce(),
      aad: conversation.aadFor(epoch),
    );

    return Uint8List.fromList([
      ...imageMagic,
      ..._epochToBytes(epoch),
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// La época con la que se cifró un blob, sin descifrarlo.
  ///
  /// Hace falta para pedir la clave correcta antes de intentar abrirlo.
  static int? epochOfBytes(Uint8List blob) {
    if (blob.length < imageMagic.length + 4) return null;
    for (var i = 0; i < imageMagic.length; i++) {
      if (blob[i] != imageMagic[i]) return null;
    }
    final o = imageMagic.length;
    return (blob[o] << 24) | (blob[o + 1] << 16) | (blob[o + 2] << 8) | blob[o + 3];
  }

  /// Devuelve los bytes originales de la imagen.
  ///
  /// Lanza [CryptoException] en vez de devolver bytes dudosos: una imagen que
  /// no abre debe mostrarse como rota, nunca como píxeles inventados.
  static Future<Uint8List> decryptBytes({
    required Uint8List blob,
    required Uint8List groupKey,
    required ConversationRef conversation,
  }) async {
    final epoch = epochOfBytes(blob);
    if (epoch == null) {
      throw const CryptoException('El archivo no es una imagen cifrada de Join.');
    }
    _ensureKeyShape(groupKey);

    final start = imageMagic.length + 4;
    // Sin el `+ 1` a propósito: un contenido de cero bytes es un blob válido,
    // no uno truncado.
    if (blob.length < start + _nonceBytes + _macBytes) {
      throw const CryptoException('La imagen cifrada está incompleta.');
    }

    final nonce = blob.sublist(start, start + _nonceBytes);
    final body = blob.sublist(start + _nonceBytes);

    try {
      final clear = await _aes.decrypt(
        SecretBox(
          body.sublist(0, body.length - _macBytes),
          nonce: nonce,
          mac: Mac(body.sublist(body.length - _macBytes)),
        ),
        secretKey: SecretKey(groupKey),
        aad: conversation.aadFor(epoch),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const CryptoException('La imagen no se puede abrir con esta clave.');
    }
  }

  // ── Interno ───────────────────────────────────────────────

  static void _ensureKeyShape(Uint8List key) {
    if (key.length != keyBytes) {
      throw const CryptoException('La clave de grupo debe ser de 32 bytes.');
    }
  }

  static List<int> _epochToBytes(int epoch) => [
        (epoch >> 24) & 0xff,
        (epoch >> 16) & 0xff,
        (epoch >> 8) & 0xff,
        epoch & 0xff,
      ];
}
