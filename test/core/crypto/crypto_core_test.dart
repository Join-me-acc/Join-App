import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:join_app/core/crypto/group_cipher.dart';
import 'package:join_app/core/crypto/join_identity.dart';
import 'package:join_app/core/crypto/recovery_phrase.dart';
import 'package:join_app/core/services/encryption_service.dart';

void main() {
  const chat = ConversationRef.clan('clan-1');
  const otroChat = ConversationRef.clan('clan-2');

  GroupKeyResolver keyring(Map<int, Uint8List> claves) =>
      (epoch) async => claves[epoch];

  group('RecoveryPhrase', () {
    test('la frase da 12 palabras y vuelve a la misma entropía', () {
      final entropia = RecoveryPhrase.newEntropy();

      final frase = RecoveryPhrase.fromEntropy(entropia);

      expect(frase.split(' ').length, 12);
      expect(RecoveryPhrase.toEntropy(frase), entropia);
    });

    test('dos frases seguidas no coinciden', () {
      final a = RecoveryPhrase.fromEntropy(RecoveryPhrase.newEntropy());
      final b = RecoveryPhrase.fromEntropy(RecoveryPhrase.newEntropy());

      expect(a, isNot(b));
    });

    test('tolera mayúsculas, saltos de línea y espacios de más', () {
      final frase = RecoveryPhrase.fromEntropy(RecoveryPhrase.newEntropy());
      final maltratada = '  ${frase.toUpperCase().replaceAll(' ', '\n  ')} ';

      expect(RecoveryPhrase.toEntropy(maltratada),
          RecoveryPhrase.toEntropy(frase));
    });

    test('una palabra cambiada no cuela: el checksum la caza', () {
      final frase = RecoveryPhrase.fromEntropy(RecoveryPhrase.newEntropy());
      final palabras = frase.split(' ');
      // Se sustituye por otra palabra de la lista, no por una inventada: el
      // caso peligroso es el que sí parece válido.
      palabras[3] = palabras[3] == 'zoo' ? 'zone' : 'zoo';

      expect(RecoveryPhrase.isValid(palabras.join(' ')), isFalse);
      expect(() => RecoveryPhrase.toEntropy(palabras.join(' ')),
          throwsA(isA<FormatException>()));
    });

    test('una frase incompleta tampoco', () {
      final frase = RecoveryPhrase.fromEntropy(RecoveryPhrase.newEntropy());

      expect(RecoveryPhrase.isValid(frase.split(' ').take(11).join(' ')), isFalse);
      expect(RecoveryPhrase.isValid(''), isFalse);
    });
  });

  group('JoinIdentity', () {
    test('la misma frase da siempre la misma identidad', () async {
      final frase = RecoveryPhrase.fromEntropy(RecoveryPhrase.newEntropy());

      final enUnMovil = await JoinIdentity.fromPhrase(frase);
      final enOtroMovil = await JoinIdentity.fromPhrase(frase);

      expect(enUnMovil.publicKeyBase64, enOtroMovil.publicKeyBase64);
    });

    test('frases distintas dan identidades distintas', () async {
      final a = await JoinIdentity.fromPhrase(
          RecoveryPhrase.fromEntropy(RecoveryPhrase.newEntropy()));
      final b = await JoinIdentity.fromPhrase(
          RecoveryPhrase.fromEntropy(RecoveryPhrase.newEntropy()));

      expect(a.publicKeyBase64, isNot(b.publicKeyBase64));
    });

    test('la clave pública es X25519 de 32 bytes', () async {
      final yo = await JoinIdentity.fromPhrase(
          RecoveryPhrase.fromEntropy(RecoveryPhrase.newEntropy()));

      expect(yo.publicKey.length, 32);
    });

    test('el destinatario abre la clave de grupo envuelta para él', () async {
      final ana = await _identidad();
      final clave = GroupCipher.newGroupKey();

      final envuelta = await JoinIdentity.wrapGroupKey(
        groupKey: clave,
        recipientPublicKey: ana.publicKey,
      );

      expect(await ana.unwrapGroupKey(envuelta), clave);
    });

    test('un tercero no abre la clave envuelta para otro', () async {
      final ana = await _identidad();
      final beto = await _identidad();

      final envuelta = await JoinIdentity.wrapGroupKey(
        groupKey: GroupCipher.newGroupKey(),
        recipientPublicKey: ana.publicKey,
      );

      expect(() => beto.unwrapGroupKey(envuelta),
          throwsA(isA<CryptoException>()));
    });

    test('envolver dos veces la misma clave da resultados distintos', () async {
      final ana = await _identidad();
      final clave = GroupCipher.newGroupKey();

      final primera = await JoinIdentity.wrapGroupKey(
          groupKey: clave, recipientPublicKey: ana.publicKey);
      final segunda = await JoinIdentity.wrapGroupKey(
          groupKey: clave, recipientPublicKey: ana.publicKey);

      // Clave efímera nueva en cada envoltorio: no se pueden correlacionar.
      expect(primera, isNot(segunda));
      expect(await ana.unwrapGroupKey(primera), clave);
      expect(await ana.unwrapGroupKey(segunda), clave);
    });

    test('un envoltorio manipulado no se abre en silencio', () async {
      final ana = await _identidad();
      final envuelta = await JoinIdentity.wrapGroupKey(
        groupKey: GroupCipher.newGroupKey(),
        recipientPublicKey: ana.publicKey,
      );

      final partes = envuelta.split('.');
      final cuerpo = base64Decode(partes[3]);
      cuerpo[0] = cuerpo[0] ^ 0xff;
      partes[3] = base64Encode(cuerpo);

      expect(() => ana.unwrapGroupKey(partes.join('.')),
          throwsA(isA<CryptoException>()));
    });

    test('un envoltorio con formato roto se rechaza', () async {
      final ana = await _identidad();

      for (final basura in ['', 'w1.a.b', 'no-es-esto', 'w1.@@@.@@@.@@@']) {
        expect(() => ana.unwrapGroupKey(basura),
            throwsA(isA<CryptoException>()), reason: basura);
      }
    });
  });

  group('GroupCipher · texto', () {
    test('el ida y vuelta devuelve el texto original', () async {
      final clave = GroupCipher.newGroupKey();
      const original = '¡Nos vemos en el parque a las 5! 🦎';

      final cifrado = await GroupCipher.encryptText(
        clearText: original, groupKey: clave, epoch: 1, conversation: chat);

      expect(cifrado, isNot(contains('parque')));
      final abierto = await GroupCipher.decryptText(
        stored: cifrado, resolveKey: keyring({1: clave}), conversation: chat);
      expect(abierto.text, original);
      expect(abierto.status, DecryptionStatus.ok);
    });

    test('conserva acentos, eñes, emojis y saltos de línea', () async {
      final clave = GroupCipher.newGroupKey();
      const original = 'Compañeros:\n— ¿Vamos a la montaña? 🏔️\n— ¡Sí! 🎉';

      final cifrado = await GroupCipher.encryptText(
        clearText: original, groupKey: clave, epoch: 7, conversation: chat);
      final abierto = await GroupCipher.decryptText(
        stored: cifrado, resolveKey: keyring({7: clave}), conversation: chat);

      expect(abierto.text, original);
    });

    test('dos cifrados del mismo texto no coinciden', () async {
      final clave = GroupCipher.newGroupKey();

      final a = await GroupCipher.encryptText(
        clearText: 'hola', groupKey: clave, epoch: 1, conversation: chat);
      final b = await GroupCipher.encryptText(
        clearText: 'hola', groupKey: clave, epoch: 1, conversation: chat);

      expect(a, isNot(b));
    });

    test('un mensaje no se puede mover a otra conversación', () async {
      final clave = GroupCipher.newGroupKey();

      final cifrado = await GroupCipher.encryptText(
        clearText: 'secreto del clan 1',
        groupKey: clave, epoch: 1, conversation: chat);

      // Misma clave, otra conversación: el dato autenticado no cuadra.
      final abierto = await GroupCipher.decryptText(
        stored: cifrado, resolveKey: keyring({1: clave}), conversation: otroChat);

      expect(abierto.status, DecryptionStatus.corrupt);
      expect(abierto.text, isEmpty);
    });

    test('un mensaje no se puede reetiquetar a otra época', () async {
      final clave = GroupCipher.newGroupKey();
      final cifrado = await GroupCipher.encryptText(
        clearText: 'hola', groupKey: clave, epoch: 1, conversation: chat);

      final falsificado = cifrado.replaceFirst('v2.1.', 'v2.2.');
      final abierto = await GroupCipher.decryptText(
        stored: falsificado,
        resolveKey: keyring({1: clave, 2: clave}),
        conversation: chat);

      expect(abierto.status, DecryptionStatus.corrupt);
    });

    test('sin la clave de esa época se informa, no se rompe', () async {
      final claveVieja = GroupCipher.newGroupKey();
      final cifrado = await GroupCipher.encryptText(
        clearText: 'de antes de que entraras',
        groupKey: claveVieja, epoch: 1, conversation: chat);

      // Quien entró en la época 2 sólo tiene la clave 2.
      final abierto = await GroupCipher.decryptText(
        stored: cifrado,
        resolveKey: keyring({2: GroupCipher.newGroupKey()}),
        conversation: chat);

      expect(abierto.status, DecryptionStatus.noKey);
      expect(abierto.text, isEmpty);
    });

    test('con la clave equivocada no devuelve basura', () async {
      final cifrado = await GroupCipher.encryptText(
        clearText: 'hola', groupKey: GroupCipher.newGroupKey(),
        epoch: 1, conversation: chat);

      final abierto = await GroupCipher.decryptText(
        stored: cifrado,
        resolveKey: keyring({1: GroupCipher.newGroupKey()}),
        conversation: chat);

      expect(abierto.status, DecryptionStatus.corrupt);
      expect(abierto.text, isEmpty);
    });

    test('un byte cambiado se detecta', () async {
      final clave = GroupCipher.newGroupKey();
      final cifrado = await GroupCipher.encryptText(
        clearText: 'transferir 100', groupKey: clave, epoch: 1, conversation: chat);

      final partes = cifrado.split('.');
      final cuerpo = base64Decode(partes[3]);
      cuerpo[2] = cuerpo[2] ^ 0x01;
      partes[3] = base64Encode(cuerpo);

      final abierto = await GroupCipher.decryptText(
        stored: partes.join('.'), resolveKey: keyring({1: clave}), conversation: chat);

      expect(abierto.status, DecryptionStatus.corrupt);
    });

    test('el texto vacío se queda vacío', () async {
      final clave = GroupCipher.newGroupKey();

      final cifrado = await GroupCipher.encryptText(
        clearText: '', groupKey: clave, epoch: 1, conversation: chat);

      expect(cifrado, isEmpty);
      final abierto = await GroupCipher.decryptText(
        stored: '', resolveKey: keyring({1: clave}), conversation: chat);
      expect(abierto.text, isEmpty);
      expect(abierto.status, DecryptionStatus.ok);
    });

    test('un texto de 20.000 caracteres sobrevive', () async {
      final clave = GroupCipher.newGroupKey();
      final largo = 'áé🦎 ' * 5000;

      final cifrado = await GroupCipher.encryptText(
        clearText: largo, groupKey: clave, epoch: 3, conversation: chat);
      final abierto = await GroupCipher.decryptText(
        stored: cifrado, resolveKey: keyring({3: clave}), conversation: chat);

      expect(abierto.text, largo);
    });

    test('ninguna forma rota lanza excepción', () async {
      final clave = GroupCipher.newGroupKey();
      const rotos = [
        'v2.', 'v2.1', 'v2.1.2', 'v2.x.aaa.bbb', 'v2.1.@@@.@@@',
        'v2.1.AAAAAAAAAAAAAAAA.QQ==', 'v2.1.2.3.4',
      ];

      for (final roto in rotos) {
        final abierto = await GroupCipher.decryptText(
          stored: roto, resolveKey: keyring({1: clave}), conversation: chat);
        expect(abierto.status, DecryptionStatus.corrupt, reason: roto);
        expect(abierto.text, isEmpty, reason: roto);
      }
    });
  });

  group('GroupCipher · historial anterior al cifrado', () {
    test('los mensajes de la clave antigua se siguen leyendo', () async {
      const original = 'mensaje de antes del cifrado real';
      final antiguo = EncryptionService.encryptText(original);

      final abierto = await GroupCipher.decryptText(
        stored: antiguo,
        resolveKey: keyring(const {}),
        conversation: chat);

      expect(abierto.text, original);
      expect(abierto.status, DecryptionStatus.legacy);
      expect(abierto.isReadable, isTrue);
    });

    test('el texto plano de siempre se muestra tal cual', () async {
      final abierto = await GroupCipher.decryptText(
        stored: 'un mensaje que nunca se cifró',
        resolveKey: keyring(const {}),
        conversation: chat);

      expect(abierto.text, 'un mensaje que nunca se cifró');
      expect(abierto.status, DecryptionStatus.legacy);
    });
  });

  group('GroupCipher · imágenes', () {
    Uint8List imagenDe(int bytes) =>
        Uint8List.fromList(List<int>.generate(bytes, (i) => i % 256));

    test('el ida y vuelta devuelve los mismos bytes', () async {
      final clave = GroupCipher.newGroupKey();
      final original = imagenDe(4096);

      final cifrada = await GroupCipher.encryptBytes(
        clearBytes: original, groupKey: clave, epoch: 2, conversation: chat);
      final abierta = await GroupCipher.decryptBytes(
        blob: cifrada, groupKey: clave, conversation: chat);

      expect(abierta, original);
    });

    test('el blob no contiene los bytes originales', () async {
      final clave = GroupCipher.newGroupKey();
      final original = Uint8List.fromList(utf8.encode('PNG secreto'));

      final cifrada = await GroupCipher.encryptBytes(
        clearBytes: original, groupKey: clave, epoch: 1, conversation: chat);

      expect(utf8.decode(cifrada, allowMalformed: true), isNot(contains('secreto')));
    });

    test('la época se lee sin descifrar, para pedir la clave correcta', () async {
      final cifrada = await GroupCipher.encryptBytes(
        clearBytes: imagenDe(64), groupKey: GroupCipher.newGroupKey(),
        epoch: 42, conversation: chat);

      expect(GroupCipher.epochOfBytes(cifrada), 42);
    });

    test('un archivo que no es de Join se rechaza', () async {
      final noEsNuestro = Uint8List.fromList(utf8.encode('GIF89a...'));

      expect(GroupCipher.epochOfBytes(noEsNuestro), isNull);
      expect(
        () => GroupCipher.decryptBytes(
          blob: noEsNuestro,
          groupKey: GroupCipher.newGroupKey(),
          conversation: chat),
        throwsA(isA<CryptoException>()));
    });

    test('con la clave equivocada no devuelve píxeles inventados', () async {
      final cifrada = await GroupCipher.encryptBytes(
        clearBytes: imagenDe(256), groupKey: GroupCipher.newGroupKey(),
        epoch: 1, conversation: chat);

      expect(
        () => GroupCipher.decryptBytes(
          blob: cifrada,
          groupKey: GroupCipher.newGroupKey(),
          conversation: chat),
        throwsA(isA<CryptoException>()));
    });

    test('una imagen no se puede mover a otra conversación', () async {
      final clave = GroupCipher.newGroupKey();
      final cifrada = await GroupCipher.encryptBytes(
        clearBytes: imagenDe(128), groupKey: clave, epoch: 1, conversation: chat);

      expect(
        () => GroupCipher.decryptBytes(
          blob: cifrada, groupKey: clave, conversation: otroChat),
        throwsA(isA<CryptoException>()));
    });

    test('un blob truncado se rechaza', () async {
      final clave = GroupCipher.newGroupKey();
      final cifrada = await GroupCipher.encryptBytes(
        clearBytes: imagenDe(512), groupKey: clave, epoch: 1, conversation: chat);

      expect(
        () => GroupCipher.decryptBytes(
          blob: cifrada.sublist(0, 14), groupKey: clave, conversation: chat),
        throwsA(isA<CryptoException>()));
    });

    test('una imagen vacía no rompe nada', () async {
      final clave = GroupCipher.newGroupKey();
      final cifrada = await GroupCipher.encryptBytes(
        clearBytes: Uint8List(0), groupKey: clave, epoch: 1, conversation: chat);

      expect(
        await GroupCipher.decryptBytes(
          blob: cifrada, groupKey: clave, conversation: chat),
        isEmpty);
    });
  });

  group('GroupCipher · claves', () {
    test('cada clave de grupo es distinta y de 32 bytes', () {
      final a = GroupCipher.newGroupKey();
      final b = GroupCipher.newGroupKey();

      expect(a.length, GroupCipher.keyBytes);
      expect(a, isNot(b));
    });

    test('una clave con el tamaño equivocado se rechaza al cifrar', () async {
      expect(
        () => GroupCipher.encryptText(
          clearText: 'hola',
          groupKey: Uint8List(16),
          epoch: 1,
          conversation: chat),
        throwsA(isA<CryptoException>()));
    });
  });
}

Future<JoinIdentity> _identidad() => JoinIdentity.fromPhrase(
      RecoveryPhrase.fromEntropy(RecoveryPhrase.newEntropy()),
    );
