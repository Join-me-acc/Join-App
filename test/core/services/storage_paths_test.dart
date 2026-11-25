import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:join_app/core/services/storage_paths.dart';

void main() {
  const uid = '2b37ab6e-0437-481d-ba2f-aed3977dc5bb';
  const otroUid = 'b8b7e1c0-7140-4f77-8acd-26c53b13dafe';

  group('StoragePaths · rutas', () {
    // Es la garantía de la que dependen las políticas del bucket: si la
    // primera carpeta deja de ser el uid, Storage rechaza la subida.
    test('toda ruta empieza por la carpeta del usuario', () {
      final rutas = [
        StoragePaths.avatar(uid, '/tmp/foto.jpg'),
        StoragePaths.activityCover(uid, 'act-1', '/tmp/foto.jpg'),
        StoragePaths.eventPhoto(uid, 'act-1', '/tmp/foto.jpg'),
        StoragePaths.chatAttachment(
          userId: uid, scope: 'clan', conversationId: 'clan-1'),
      ];

      for (final ruta in rutas) {
        expect(ruta.split('/').first, uid, reason: ruta);
      }
    });

    test('la ruta nunca queda bajo el id de otro usuario', () {
      final ruta = StoragePaths.avatar(uid, 'foto.png');

      expect(ruta.contains(otroUid), isFalse);
    });

    test('la foto de recap conserva la actividad en la ruta', () {
      final ruta = StoragePaths.eventPhoto(uid, 'act-42', 'foto.png');

      expect(ruta, startsWith('$uid/recap/act-42/'));
      expect(ruta, endsWith('.png'));
    });

    test('la portada conserva la actividad en el nombre', () {
      final ruta = StoragePaths.activityCover(uid, 'act-42', 'foto.webp');

      expect(ruta, startsWith('$uid/act_act-42_'));
      expect(ruta, endsWith('.webp'));
    });

    test('sin sesión no se construye ninguna ruta', () {
      expect(
        () => StoragePaths.avatar('', 'foto.png'),
        throwsA(isA<StorageUploadException>()),
      );
    });

    test('el adjunto de chat lleva la conversación en la ruta', () {
      // Las políticas del bucket leen scope e id de aquí para exigir que
      // quien sube sea miembro de esa conversación.
      final ruta = StoragePaths.chatAttachment(
        userId: uid, scope: 'activity', conversationId: 'act-9');

      expect(ruta, startsWith('$uid/activity/act-9/'));
      expect(ruta, endsWith('.bin'));
    });

    test('un adjunto sin conversación no se construye', () {
      expect(
        () => StoragePaths.chatAttachment(
            userId: uid, scope: 'clan', conversationId: ''),
        throwsA(isA<StorageUploadException>()),
      );
    });
  });

  group('StoragePaths · tipo de archivo', () {
    test('normaliza la extensión a minúsculas', () {
      expect(StoragePaths.extensionOf('/tmp/IMG_0042.JPG'), 'jpg');
      expect(StoragePaths.extensionOf('/tmp/foto.PNG'), 'png');
    });

    test('acepta lo que devuelve la cámara de iOS', () {
      expect(StoragePaths.extensionOf('/tmp/IMG_1.HEIC'), 'heic');
    });

    test('rechaza lo que no es imagen', () {
      for (final ruta in ['nota.txt', 'app.apk', 'video.mp4', 'script.php']) {
        expect(
          () => StoragePaths.extensionOf(ruta),
          throwsA(isA<StorageUploadException>()),
          reason: ruta,
        );
      }
    });

    test('un archivo sin extensión no pasa', () {
      expect(
        () => StoragePaths.extensionOf('/tmp/archivo'),
        throwsA(isA<StorageUploadException>()),
      );
    });

    test('el Content-Type coincide con la extensión', () {
      expect(StoragePaths.imageOptions('a.jpg').contentType, 'image/jpeg');
      expect(StoragePaths.imageOptions('a.jpeg').contentType, 'image/jpeg');
      expect(StoragePaths.imageOptions('a.png').contentType, 'image/png');
      expect(StoragePaths.imageOptions('a.webp').contentType, 'image/webp');
    });

    test('los MIME declarados son los que aceptan los buckets', () {
      // Debe cuadrar con allowed_mime_types de la migración
      // 20260807120000_harden_storage.sql.
      expect(
        StoragePaths.allowedImageTypes.values.toSet(),
        {'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'},
      );
    });
  });

  group('StoragePaths · tamaño', () {
    late Directory temporal;

    setUp(() => temporal = Directory.systemTemp.createTempSync('join_storage'));
    tearDown(() => temporal.deleteSync(recursive: true));

    File archivoDe(int bytes) {
      final file = File('${temporal.path}/archivo.png');
      file.writeAsBytesSync(List<int>.filled(bytes, 0));
      return file;
    }

    test('deja pasar lo que cabe en el límite', () {
      expect(
        () => StoragePaths.ensureWithinLimit(
          archivoDe(1024),
          StoragePaths.avatarMaxBytes,
        ),
        returnsNormally,
      );
    });

    test('corta el avatar que se pasa de 5 MB', () {
      expect(
        () => StoragePaths.ensureWithinLimit(
          archivoDe(StoragePaths.avatarMaxBytes + 1),
          StoragePaths.avatarMaxBytes,
        ),
        throwsA(isA<StorageUploadException>()),
      );
    });

    test('el error dice cuánto pesa y cuánto se admite', () {
      // El usuario tiene que poder actuar sobre el mensaje.
      try {
        StoragePaths.ensureWithinLimit(
          archivoDe(6 * 1024 * 1024),
          StoragePaths.avatarMaxBytes,
        );
        fail('debería haber lanzado');
      } on StorageUploadException catch (e) {
        expect(e.message, contains('6.0 MB'));
        expect(e.message, contains('5.0 MB'));
      }
    });
  });
}
