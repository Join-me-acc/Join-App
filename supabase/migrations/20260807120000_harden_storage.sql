-- ════════════════════════════════════════════════════════════════════
--  ENDURECER STORAGE
--
--  Antes de esta migración, cualquier usuario autenticado podía subir
--  a cualquiera de los tres buckets un archivo de cualquier tamaño y de
--  cualquier tipo, con el nombre que quisiera. La anon key va dentro del
--  APK, así que "autenticado" es cualquiera que se registre.
--
--  Tres candados, en este orden:
--
--   1. Tamaño y tipo por bucket. Los aplica el propio Storage antes de
--      escribir nada; no dependen de que el cliente se porte bien.
--   2. Cada objeto vive bajo una carpeta con el id de su dueño, y las
--      políticas de escritura sólo aceptan la carpeta propia. Así nadie
--      pisa el avatar de otro ni ocupa un nombre ajeno.
--   3. Borrar y actualizar siguen exigiendo `owner`, como ya hacían.
--
--  La lectura sigue siendo pública: los tres buckets son públicos y las
--  URLs que se guardan en la base de datos se sirven sin pasar por RLS.
--  Restringir aquí el SELECT no ocultaría nada mientras el bucket lo sea.
-- ════════════════════════════════════════════════════════════════════


-- ══ 1. LÍMITES DE TAMAÑO Y TIPO ══════════════════════════════════════
-- Los MIME admitidos deben coincidir con StoragePaths.allowedImageTypes
-- (lib/core/services/storage_paths.dart). HEIC/HEIF entran porque es lo
-- que devuelve la cámara de iOS.

UPDATE storage.buckets
SET file_size_limit  = 5242880,   -- 5 MiB: un avatar se ve en miniatura
    allowed_mime_types = ARRAY[
      'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'
    ]
WHERE id = 'avatars';

UPDATE storage.buckets
SET file_size_limit  = 10485760,  -- 10 MiB: portadas y fotos de chat/recap
    allowed_mime_types = ARRAY[
      'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'
    ]
WHERE id IN ('activities', 'chat');


-- ══ 2. ESCRITURA SÓLO EN LA CARPETA PROPIA ═══════════════════════════
-- storage.foldername('<uid>/foto.jpg') devuelve {<uid>}. Un objeto suelto
-- en la raíz devuelve {}, y {}[1] es NULL: la comparación falla y la
-- subida se rechaza. Es justo lo que queremos — sin carpeta no hay dueño
-- verificable en la ruta.

DROP POLICY IF EXISTS "Inserción de objetos para autenticados" ON storage.objects;
DROP POLICY IF EXISTS "Subida en la carpeta propia" ON storage.objects;
CREATE POLICY "Subida en la carpeta propia"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id IN ('activities', 'avatars', 'chat')
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Actualización de objetos por dueño" ON storage.objects;
DROP POLICY IF EXISTS "Actualización de objetos propios" ON storage.objects;
CREATE POLICY "Actualización de objetos propios"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id IN ('activities', 'avatars', 'chat')
  AND owner = auth.uid()
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id IN ('activities', 'avatars', 'chat')
  AND owner = auth.uid()
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- El USING anterior era `bucket_id IN (...)` a secas y el dueño sólo se
-- comprobaba en el WITH CHECK, así que se podía apuntar a un objeto ajeno
-- mientras el resultado quedara a nombre propio.

DROP POLICY IF EXISTS "Eliminación de objetos por dueño" ON storage.objects;
DROP POLICY IF EXISTS "Eliminación de objetos propios" ON storage.objects;
CREATE POLICY "Eliminación de objetos propios"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id IN ('activities', 'avatars', 'chat')
  AND owner = auth.uid()
  AND (storage.foldername(name))[1] = auth.uid()::text
);
