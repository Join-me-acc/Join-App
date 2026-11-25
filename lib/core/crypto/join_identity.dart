import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'recovery_phrase.dart';

/// Error de cualquier operación criptográfica que no se pueda completar.
///
/// Se distingue de [FormatException] a propósito: aquí el dato tiene la forma
/// correcta pero la clave no abre, que es un caso muy distinto de cara al
/// usuario ("este mensaje no es para ti" frente a "esto está corrupto").
class CryptoException implements Exception {
  const CryptoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// La identidad criptográfica de un usuario: un par X25519 del que sólo la
/// parte pública llega al servidor.
///
/// Se deriva de la frase de recuperación de forma determinista, así que la
/// misma frase produce siempre el mismo par en cualquier dispositivo.
class JoinIdentity {
  const JoinIdentity._(this._keyPair, this.publicKey);

  final SimpleKeyPair _keyPair;

  /// La parte pública, tal y como se publica en `user_keys`.
  final Uint8List publicKey;

  static final _x25519 = X25519();
  static final _aes = AesGcm.with256bits();

  /// Etiquetas de dominio de HKDF. Separan usos que jamás deben compartir
  /// clave aunque partan del mismo secreto.
  static const _identityInfo = 'join-identity-x25519-v1';
  static const _wrapInfo = 'join-key-wrap-v1';

  /// Deriva la identidad de una frase de recuperación.
  static Future<JoinIdentity> fromPhrase(String phrase) async {
    final seed = RecoveryPhrase.seedOf(phrase);
    final material = await Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    ).deriveKey(
      secretKey: SecretKey(seed),
      nonce: const <int>[],
      info: utf8.encode(_identityInfo),
    );

    final keyPair = await _x25519.newKeyPairFromSeed(
      await material.extractBytes(),
    );
    final public = await keyPair.extractPublicKey();
    return JoinIdentity._(keyPair, Uint8List.fromList(public.bytes));
  }

  /// La clave pública en Base64, que es como viaja y como se guarda.
  String get publicKeyBase64 => base64Encode(publicKey);

  /// Envuelve [groupKey] para que sólo el dueño de [recipientPublicKey] pueda
  /// abrirla.
  ///
  /// Usa una clave efímera distinta en cada llamada: quien capture el
  /// resultado no puede relacionarlo con otros envoltorios del mismo emisor,
  /// y comprometer la identidad de quien envuelve no descubre las claves ya
  /// repartidas.
  static Future<String> wrapGroupKey({
    required Uint8List groupKey,
    required Uint8List recipientPublicKey,
  }) async {
    final ephemeral = await _x25519.newKeyPair();
    final ephemeralPublic = await ephemeral.extractPublicKey();

    final wrappingKey = await _deriveWrappingKey(
      keyPair: ephemeral,
      remotePublicKey: recipientPublicKey,
      ephemeralPublicKey: Uint8List.fromList(ephemeralPublic.bytes),
      recipientPublicKey: recipientPublicKey,
    );

    final box = await _aes.encrypt(
      groupKey,
      secretKey: wrappingKey,
      nonce: _aes.newNonce(),
    );

    return [
      'w1',
      base64Encode(ephemeralPublic.bytes),
      base64Encode(box.nonce),
      base64Encode(box.cipherText + box.mac.bytes),
    ].join('.');
  }

  /// Abre un envoltorio creado por [wrapGroupKey] para esta identidad.
  Future<Uint8List> unwrapGroupKey(String wrapped) async {
    final parts = wrapped.split('.');
    if (parts.length != 4 || parts.first != 'w1') {
      throw const CryptoException('El envoltorio de la clave no tiene el formato esperado.');
    }

    final Uint8List ephemeralPublic;
    final List<int> nonce;
    final List<int> payload;
    try {
      ephemeralPublic = base64Decode(parts[1]);
      nonce = base64Decode(parts[2]);
      payload = base64Decode(parts[3]);
    } on FormatException {
      throw const CryptoException('El envoltorio de la clave está corrupto.');
    }

    if (payload.length <= 16) {
      throw const CryptoException('El envoltorio de la clave está incompleto.');
    }

    final wrappingKey = await _deriveWrappingKey(
      keyPair: _keyPair,
      remotePublicKey: ephemeralPublic,
      ephemeralPublicKey: ephemeralPublic,
      recipientPublicKey: publicKey,
    );

    try {
      final clear = await _aes.decrypt(
        SecretBox(
          payload.sublist(0, payload.length - 16),
          nonce: nonce,
          mac: Mac(payload.sublist(payload.length - 16)),
        ),
        secretKey: wrappingKey,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const CryptoException(
        'Esta clave no está envuelta para ti: no puedes abrir la conversación.',
      );
    }
  }

  /// El secreto compartido de X25519 no se usa nunca tal cual: pasa por HKDF
  /// junto a las dos claves públicas. Incluirlas en el salt ata el resultado
  /// a este par concreto de interlocutores.
  static Future<SecretKey> _deriveWrappingKey({
    required SimpleKeyPair keyPair,
    required List<int> remotePublicKey,
    required Uint8List ephemeralPublicKey,
    required Uint8List recipientPublicKey,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(
        remotePublicKey,
        type: KeyPairType.x25519,
      ),
    );

    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      nonce: <int>[...ephemeralPublicKey, ...recipientPublicKey],
      info: utf8.encode(_wrapInfo),
    );
  }
}
