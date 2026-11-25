-- ════════════════════════════════════════════════════════════════════
--  FOTO DE PERFIL DESDE GOOGLE
--  Migración: 20261124180000_profile_photo_from_google.sql
--
--  handle_new_user buscaba la foto en avatarUrl / profileImageUrl, claves
--  que Google no envía: Google la manda como avatar_url y picture. Los
--  usuarios que entraban con Google quedaban sin foto y, en la pantalla de
--  solicitudes, la app rellenaba el hueco con la foto de stock de otra
--  persona.
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
  v_search_code TEXT;
BEGIN
  v_search_code := public.generate_unique_search_code();

  INSERT INTO public.profiles (
    id, display_name, email, profile_image_url, setup_completed, search_code
  ) VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'fullName',
             new.raw_user_meta_data->>'full_name',
             new.raw_user_meta_data->>'name',
             split_part(new.email, '@', 1)),
    new.email,
    COALESCE(NULLIF(new.raw_user_meta_data->>'avatarUrl', ''),
             NULLIF(new.raw_user_meta_data->>'profileImageUrl', ''),
             NULLIF(new.raw_user_meta_data->>'avatar_url', ''),
             NULLIF(new.raw_user_meta_data->>'picture', ''),
             ''),
    FALSE,
    v_search_code
  );
  RETURN NEW;
END;
$function$;

-- Rellenar a quienes ya quedaron sin foto.
UPDATE public.profiles p
   SET profile_image_url = COALESCE(NULLIF(u.raw_user_meta_data->>'avatar_url', ''),
                                    NULLIF(u.raw_user_meta_data->>'picture', ''))
  FROM auth.users u
 WHERE u.id = p.id
   AND COALESCE(p.profile_image_url, '') = ''
   AND COALESCE(NULLIF(u.raw_user_meta_data->>'avatar_url', ''),
                NULLIF(u.raw_user_meta_data->>'picture', '')) IS NOT NULL;
