import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Excepción de una subida rechazada antes de salir del dispositivo.
///
/// Existe para que la interfaz pueda mostrar el motivo en castellano en vez
/// del 400/413 opaco que devolvería Storage.
class StorageUploadException implements Exception {
  const StorageUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Rutas y validación de todo lo que la app sube a Supabase Storage.
///
/// Dos reglas gobiernan este archivo:
///
/// 1. **Cada objeto vive bajo una carpeta con el id de quien lo sube.** Las
///    políticas de Storage lo exigen (`(storage.foldername(name))[1] =
///    auth.uid()`), así que nadie puede escribir —ni sobrescribir— en el
///    espacio de otro. Construir la ruta a mano se salta esa garantía.
/// 2. **El tipo y el tamaño se comprueban aquí y en el servidor.** Aquí para
///    dar un mensaje entendible; en el servidor porque el cliente miente.
class StoragePaths {
  const StoragePaths._();

  static const String avatarsBucket = 'avatars';
  static const String activitiesBucket = 'activities';
  static const String chatBucket = 'chat';

  /// Extensiones admitidas y el `Content-Type` que le corresponde a cada una.
  ///
  /// Debe coincidir con `allowed_mime_types` de los buckets (ver la migración
  /// `20260807120000_harden_storage.sql`).
  static const Map<String, String> allowedImageTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
  };

  /// Límite del avatar: se muestra en miniatura, no necesita más.
  static const int avatarMaxBytes = 5 * 1024 * 1024;

  /// Límite de portadas y fotos de chat o recap.
  static const int imageMaxBytes = 10 * 1024 * 1024;

  // ── Rutas ─────────────────────────────────────────────────

  /// `<uid>/avatar_<ts>.<ext>`
  static String avatar(String userId, String sourcePath) =>
      '${_folder(userId)}/avatar_${_stamp()}.${extensionOf(sourcePath)}';

  /// `<uid>/<scope>/<conversación>/<ts>.bin`
  ///
  /// La conversación va en la ruta porque las políticas del bucket la miran:
  /// sólo sus miembros pueden subir ahí y leer de ahí. La extensión es `.bin`
  /// y no la de la imagen porque lo que se sube es el blob cifrado — decir
  /// `.jpg` sería mentir sobre el contenido.
  static String chatAttachment({
    required String userId,
    required String scope,
    required String conversationId,
  }) {
    if (conversationId.isEmpty) {
      throw const StorageUploadException(
        'No se sabe a qué conversación pertenece la imagen.',
      );
    }
    return '${_folder(userId)}/$scope/$conversationId/${_stamp()}.bin';
  }

  /// `<uid>/act_<actividad>_<ts>.<ext>`
  static String activityCover(
    String userId,
    String activityId,
    String sourcePath,
  ) =>
      '${_folder(userId)}/act_${activityId}_${_stamp()}.${extensionOf(sourcePath)}';

  /// `<uid>/recap/<actividad>/<ts>.<ext>`
  static String eventPhoto(
    String userId,
    String activityId,
    String sourcePath,
  ) =>
      '${_folder(userId)}/recap/$activityId/${_stamp()}.${extensionOf(sourcePath)}';

  // ── Validación ────────────────────────────────────────────

  /// Extensión en minúsculas, o [StorageUploadException] si no es una imagen
  /// que los buckets acepten.
  static String extensionOf(String sourcePath) {
    final dot = sourcePath.lastIndexOf('.');
    final ext = dot == -1 ? '' : sourcePath.substring(dot + 1).toLowerCase();
    if (!allowedImageTypes.containsKey(ext)) {
      throw const StorageUploadException(
        'Solo se admiten imágenes JPG, PNG, WEBP o HEIC.',
      );
    }
    return ext;
  }

  /// Opciones de subida con el `Content-Type` correcto.
  ///
  /// Sin esto el cliente lo deduce del nombre y una extensión rara acaba en
  /// `application/octet-stream`, que el bucket rechaza sin explicar por qué.
  static FileOptions imageOptions(String sourcePath) =>
      FileOptions(contentType: allowedImageTypes[extensionOf(sourcePath)]);

  /// Lanza [StorageUploadException] si el archivo pasa de [maxBytes].
  static void ensureWithinLimit(File file, int maxBytes) {
    final size = file.lengthSync();
    if (size > maxBytes) {
      throw StorageUploadException(
        'La imagen pesa ${_asMegabytes(size)} MB y el máximo es '
        '${_asMegabytes(maxBytes)} MB.',
      );
    }
  }

  // ── Interno ───────────────────────────────────────────────

  /// El id del usuario es el nombre de la carpeta, así que tiene que ser un
  /// id real: una cadena vacía dejaría la ruta en la raíz y Storage la
  /// rechazaría con un 403 difícil de leer.
  static String _folder(String userId) {
    if (userId.isEmpty) {
      throw const StorageUploadException(
        'No hay sesión activa para subir la imagen.',
      );
    }
    return userId;
  }

  static String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  static String _asMegabytes(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(1);
}
