-- ════════════════════════════════════════════════════════════════════
--  CIFRADO DE EXTREMO A EXTREMO REAL
--
--  Hasta ahora la interfaz prometía "cifrado de extremo a extremo" y el
--  cifrado usaba una clave AES fija dentro del binario: cualquiera que
--  abriera el APK podía leer todos los chats. Esta migración añade lo
--  que hace falta para que la promesa sea cierta.
--
--  El modelo, en corto:
--
--   · Cada usuario tiene un par X25519. Aquí sólo llega la parte pública
--     (`user_keys`); la privada se deriva de una frase de recuperación de
--     12 palabras y vive en el llavero del móvil. El servidor no la ve.
--
--   · Cada conversación tiene una clave AES-256 por *época*
--     (`conversation_epochs`). Los mensajes se cifran con ella.
--
--   · Esa clave se guarda una vez por miembro, envuelta con su clave
--     pública (`epoch_keys`). Sólo el destinatario puede abrir la suya.
--
--   · Al entrar o salir alguien —o al cambiar su clave— se abre una época
--     nueva. Quien entra no lee lo anterior; quien sale no lee lo nuevo.
--
--  Lo que el servidor sigue viendo, y conviene no olvidar: quién habla
--  con quién, cuándo y cuánto. El cifrado protege el contenido, no los
--  metadatos.
-- ════════════════════════════════════════════════════════════════════


-- ══ 1. CLAVES PÚBLICAS ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.user_keys (
  user_id     uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  public_key  text NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_keys ENABLE ROW LEVEL SECURITY;

-- Las públicas tienen que ser legibles por todos: para meter a alguien en
-- una conversación hay que envolver la clave del grupo con la suya.
DROP POLICY IF EXISTS "Leer claves publicas" ON public.user_keys;
CREATE POLICY "Leer claves publicas"
ON public.user_keys FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Publicar mi clave publica" ON public.user_keys;
CREATE POLICY "Publicar mi clave publica"
ON public.user_keys FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Reinstalar sin la frase genera una identidad nueva, así que la clave
-- publicada tiene que poder sustituirse. Sólo por su dueño.
DROP POLICY IF EXISTS "Actualizar mi clave publica" ON public.user_keys;
CREATE POLICY "Actualizar mi clave publica"
ON public.user_keys FOR UPDATE TO authenticated
USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ══ 2. QUIÉN ES MIEMBRO DE QUÉ ═══════════════════════════════════════
-- `is_activity_member` ya existía; para clanes no había equivalente.

CREATE OR REPLACE FUNCTION public.is_clan_member(p_clan_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.clan_members cm
     WHERE cm.clan_id = p_clan_id AND cm.user_id = p_user_id
  );
$$;

-- Resuelve la pertenencia sin que quien llama tenga que saber si el
-- ámbito es una actividad o un clan.
CREATE OR REPLACE FUNCTION public.is_conversation_member(
  p_scope text, p_scope_id uuid, p_user_id uuid
)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT CASE p_scope
    WHEN 'activity' THEN public.is_activity_member(p_scope_id, p_user_id)
    WHEN 'clan'     THEN public.is_clan_member(p_scope_id, p_user_id)
    ELSE false
  END;
$$;


-- ══ 3. ÉPOCAS DE CADA CONVERSACIÓN ═══════════════════════════════════

CREATE TABLE IF NOT EXISTS public.conversation_epochs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scope         text NOT NULL CHECK (scope IN ('activity', 'clan')),
  scope_id      uuid NOT NULL,
  epoch         integer NOT NULL CHECK (epoch > 0),
  -- Huella del conjunto (miembro, clave pública) para el que se repartió
  -- esta época. Es lo que permite a cualquier cliente decidir si hay que
  -- rotar sin leer las claves envueltas de los demás. Cambia tanto si
  -- entra o sale alguien como si un miembro reinstala y cambia de clave.
  members_hash  text NOT NULL,
  member_ids    uuid[] NOT NULL,
  created_by    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (scope, scope_id, epoch)
);

CREATE INDEX IF NOT EXISTS idx_epoch_conversation
  ON public.conversation_epochs (scope, scope_id, epoch DESC);

ALTER TABLE public.conversation_epochs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ver las epocas de mis conversaciones" ON public.conversation_epochs;
CREATE POLICY "Ver las epocas de mis conversaciones"
ON public.conversation_epochs FOR SELECT TO authenticated
USING (public.is_conversation_member(scope, scope_id, auth.uid()));

-- Cualquier miembro puede abrir una época: la rotación la dispara quien
-- primero note el cambio, y el UNIQUE de arriba resuelve los empates.
DROP POLICY IF EXISTS "Abrir una epoca en mis conversaciones" ON public.conversation_epochs;
CREATE POLICY "Abrir una epoca en mis conversaciones"
ON public.conversation_epochs FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = created_by
  AND public.is_conversation_member(scope, scope_id, auth.uid())
);

-- Sin UPDATE ni DELETE a propósito: una época es un hecho consumado.
-- Reescribirla dejaría ilegibles los mensajes que ya se cifraron con ella.


-- ══ 4. LA CLAVE DE LA ÉPOCA, ENVUELTA PARA CADA MIEMBRO ══════════════

CREATE TABLE IF NOT EXISTS public.epoch_keys (
  epoch_id     uuid NOT NULL REFERENCES public.conversation_epochs(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  wrapped_key  text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (epoch_id, user_id)
);

ALTER TABLE public.epoch_keys ENABLE ROW LEVEL SECURITY;

-- Cada uno ve sólo su envoltorio. Los de los demás no le sirven de nada
-- —no puede abrirlos—, pero tampoco tiene por qué recogerlos.
DROP POLICY IF EXISTS "Ver solo mi copia de la clave" ON public.epoch_keys;
CREATE POLICY "Ver solo mi copia de la clave"
ON public.epoch_keys FOR SELECT TO authenticated
USING (auth.uid() = user_id);

-- Quien abre la época reparte la clave, así que inserta filas a nombre de
-- otros. Se le exige ser miembro de esa misma conversación.
--
-- El riesgo que queda es que un miembro reparta un envoltorio inservible
-- y deje a otro sin poder leer. Es un incordio, no una fuga: la clave
-- privada del afectado sigue siendo suya y nada se descifra de más. La
-- clave primaria impide además pisar un envoltorio ya repartido.
DROP POLICY IF EXISTS "Repartir claves en mis conversaciones" ON public.epoch_keys;
CREATE POLICY "Repartir claves en mis conversaciones"
ON public.epoch_keys FOR INSERT TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.conversation_epochs e
     WHERE e.id = epoch_keys.epoch_id
       AND public.is_conversation_member(e.scope, e.scope_id, auth.uid())
  )
);


-- ══ 5. PERMISOS DE TABLA ═════════════════════════════════════════════
-- Las políticas de arriba son TO authenticated; anon no pinta nada aquí.

GRANT SELECT, INSERT, UPDATE ON public.user_keys TO authenticated;
GRANT SELECT, INSERT ON public.conversation_epochs TO authenticated;
GRANT SELECT, INSERT ON public.epoch_keys TO authenticated;

REVOKE ALL ON public.user_keys FROM anon;
REVOKE ALL ON public.conversation_epochs FROM anon;
REVOKE ALL ON public.epoch_keys FROM anon;


-- ══ 6. EL BUCKET DEL CHAT DEJA DE SER PÚBLICO ════════════════════════
-- Las imágenes se suben ya cifradas, pero un bucket público serviría el
-- blob a cualquiera con la URL. No revelaría el contenido —está cifrado—
-- y aun así no hay motivo para regalarlo: el tamaño y el momento de cada
-- foto son metadatos.
--
-- Al ir cifradas dejan de ser `image/*` y pasan a ser datos opacos, así
-- que el bucket tiene que admitir application/octet-stream. El límite de
-- 10 MiB se mantiene; el cifrado sólo añade 40 bytes de cabecera.

UPDATE storage.buckets
SET public = false,
    allowed_mime_types = ARRAY['application/octet-stream']
WHERE id = 'chat';

-- Los adjuntos del chat pasan a colgar de
--   <uid>/<scope>/<id de la conversación>/<archivo>
-- para que la conversación esté en la propia ruta y las políticas puedan
-- exigir pertenencia. Sin eso, lo más fino posible sería "cualquier
-- autenticado lee cualquier blob", que aunque no revela contenido regala
-- el tamaño y la hora de cada foto.
CREATE OR REPLACE FUNCTION public.chat_object_belongs_to_member(
  p_name text, p_user_id uuid
)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  parts     text[];
  v_scope   text;
  v_scope_id uuid;
BEGIN
  parts := string_to_array(p_name, '/');
  -- <uid>/<scope>/<id>/<archivo>
  IF parts IS NULL OR array_length(parts, 1) < 4 THEN
    RETURN false;
  END IF;

  v_scope := parts[2];
  BEGIN
    v_scope_id := parts[3]::uuid;
  EXCEPTION WHEN others THEN
    -- Una ruta que no cuadra no es un error: simplemente no da acceso.
    RETURN false;
  END;

  RETURN public.is_conversation_member(v_scope, v_scope_id, p_user_id);
END;
$$;

-- Con el bucket privado, la lectura del chat pasa por RLS. Los otros dos
-- buckets siguen siendo públicos: sus imágenes se muestran por URL.
DROP POLICY IF EXISTS "Lectura pública de objetos" ON storage.objects;
CREATE POLICY "Lectura pública de objetos"
ON storage.objects FOR SELECT
USING (bucket_id IN ('activities', 'avatars'));

DROP POLICY IF EXISTS "Leer adjuntos de mis conversaciones" ON storage.objects;
CREATE POLICY "Leer adjuntos de mis conversaciones"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'chat'
  AND public.chat_object_belongs_to_member(name, auth.uid())
);

-- Y para subir, además de la carpeta propia, tiene que ser una
-- conversación en la que el usuario esté.
DROP POLICY IF EXISTS "Subida en la carpeta propia" ON storage.objects;
CREATE POLICY "Subida en la carpeta propia"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id IN ('activities', 'avatars', 'chat')
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND (
    bucket_id <> 'chat'
    OR public.chat_object_belongs_to_member(name, auth.uid())
  )
);
