-- ════════════════════════════════════════════════════════════════════
--  CICLO DE VIDA DE UN PLAN: TERMINA, SE DESPIDE Y SE RECUERDA
--  Migración: 20261124160000_activity_lifecycle.sql
--
--  Hasta ahora un plan no terminaba nunca: seguía en el inicio meses
--  después, su chat quedaba abierto para siempre, el estado 'completed'
--  no lo asignaba nadie (y por eso el Mural de Recuerdos salía vacío) y la
--  pantalla de calificación no guardaba nada.
--
--  Reglas (hora de Perú, America/Lima):
--
--   · El plan TERMINA al acabar el día en que termina el evento
--     (inicio + duración). Desde ese momento sale del inicio.
--   · El CHAT sigue abierto 2 días más para despedirse, compartir fotos y
--     armar un clan. Después queda en sólo lectura.
--   · Al terminar, los integrantes reciben un aviso para calificar y subir
--     su foto al mural; un día antes de cerrar el chat, otro aviso que
--     sugiere crear un clan para seguir en contacto.
--   · Calificar sólo se puede con el plan terminado, una vez por persona y
--     no al propio plan. La nota del organizador es el promedio de las
--     calificaciones de todos sus planes.
--
--  Las fechas se calculan en el servidor a partir de event_datetime: no
--  hace falta un proceso para que el chat se cierre a tiempo. El barrido
--  periódico (pg_cron) sólo marca 'completed' y envía los avisos, y es
--  idempotente: la app también lo invoca al abrirse por si cron no corre.
-- ════════════════════════════════════════════════════════════════════


-- ══ 1. FECHAS DEL CICLO ══════════════════════════════════════════════

-- Fin del día (hora de Lima) en que termina el evento.
CREATE OR REPLACE FUNCTION public.activity_ends_at(
  p_event_datetime timestamptz, p_duration_minutes integer)
RETURNS timestamptz
LANGUAGE sql STABLE
AS $$
  SELECT (
    date_trunc(
      'day',
      (p_event_datetime
         + make_interval(mins => GREATEST(COALESCE(p_duration_minutes, 0), 0)))
        AT TIME ZONE 'America/Lima'
    ) + interval '1 day'
  ) AT TIME ZONE 'America/Lima';
$$;

-- El chat se cierra dos días después.
CREATE OR REPLACE FUNCTION public.activity_chat_closes_at(
  p_event_datetime timestamptz, p_duration_minutes integer)
RETURNS timestamptz
LANGUAGE sql STABLE
AS $$
  SELECT public.activity_ends_at(p_event_datetime, p_duration_minutes)
         + interval '2 days';
$$;

CREATE OR REPLACE FUNCTION public.activity_has_ended(p_activity_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.activities a
     WHERE a.id = p_activity_id
       AND now() >= public.activity_ends_at(a.event_datetime, a.duration_minutes)
  );
$$;

CREATE OR REPLACE FUNCTION public.activity_chat_is_open(p_activity_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.activities a
     WHERE a.id = p_activity_id
       AND now() < public.activity_chat_closes_at(a.event_datetime, a.duration_minutes)
  );
$$;


-- ══ 2. EL CHAT SE CIERRA ═════════════════════════════════════════════
-- Se sigue pudiendo leer; escribir, no. Aplica también a las tarjetas de
-- resultado de juegos y a las imágenes, que son mensajes.

DROP POLICY IF EXISTS "Escribir en el chat de mis actividades" ON public.chat_messages;
CREATE POLICY "Escribir en el chat de mis actividades"
ON public.chat_messages FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND public.is_activity_member(activity_id, auth.uid())
  AND public.activity_chat_is_open(activity_id)
);


-- ══ 3. CALIFICACIONES ════════════════════════════════════════════════

DROP POLICY IF EXISTS "Valorar actividades a las que asisti" ON public.event_feedback;
CREATE POLICY "Valorar actividades a las que asisti"
ON public.event_feedback FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND public.is_activity_member(activity_id, auth.uid())
  AND NOT public.is_activity_organizer(activity_id, auth.uid())
  AND public.activity_has_ended(activity_id)
  AND group_rating BETWEEN 1 AND 5
  AND attendance_score BETWEEN 1 AND 5
);

-- La nota del organizador: promedio de todas las calificaciones que
-- recibieron sus planes. Antes profiles.rating existía pero nadie la
-- actualizaba, y todos los perfiles mostraban 0.0.
CREATE OR REPLACE FUNCTION public.refresh_organizer_rating(p_organizer_id uuid)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  UPDATE public.profiles p
     SET rating = COALESCE(s.avg_rating, 0),
         rating_count = COALESCE(s.total, 0)
    FROM (
      SELECT round(avg(f.group_rating)::numeric, 2) AS avg_rating,
             count(*)::int AS total
        FROM public.event_feedback f
        JOIN public.activities a ON a.id = f.activity_id
       WHERE a.organizer_id = p_organizer_id
    ) s
   WHERE p.id = p_organizer_id;
$$;

CREATE OR REPLACE FUNCTION public.handle_event_feedback_rating()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_organizer uuid;
  v_activity  uuid := COALESCE(NEW.activity_id, OLD.activity_id);
BEGIN
  SELECT organizer_id INTO v_organizer FROM public.activities WHERE id = v_activity;
  IF v_organizer IS NOT NULL THEN
    PERFORM public.refresh_organizer_rating(v_organizer);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_event_feedback_rating ON public.event_feedback;
CREATE TRIGGER trg_event_feedback_rating
  AFTER INSERT OR UPDATE OR DELETE ON public.event_feedback
  FOR EACH ROW EXECUTE FUNCTION public.handle_event_feedback_rating();

-- ¿Qué planes terminados me faltan calificar? La app lo usa para el aviso
-- del chat y del detalle.
CREATE OR REPLACE FUNCTION public.my_pending_ratings()
RETURNS TABLE (activity_id uuid, title text, ends_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.title::text,
         public.activity_ends_at(a.event_datetime, a.duration_minutes)
    FROM public.activities a
    JOIN public.activity_participants ap
      ON ap.activity_id = a.id AND ap.user_id = auth.uid()
   WHERE a.organizer_id <> auth.uid()
     AND now() >= public.activity_ends_at(a.event_datetime, a.duration_minutes)
     AND now() < public.activity_ends_at(a.event_datetime, a.duration_minutes)
                 + interval '30 days'
     AND NOT EXISTS (
           SELECT 1 FROM public.event_feedback f
            WHERE f.activity_id = a.id AND f.user_id = auth.uid())
   ORDER BY 3 DESC;
$$;


-- ══ 4. MURAL DE RECUERDOS ════════════════════════════════════════════
-- Cada integrante sube sus fotos al mural del plan, que es del organizador.
-- Desde el perfil de cada participante el recuerdo enlaza a ese mural.
-- Las fotos se suben desde el día del evento: antes no hay recuerdo.

DROP POLICY IF EXISTS "Subir fotos a mis actividades" ON public.event_photos;
CREATE POLICY "Subir fotos a mis actividades"
ON public.event_photos FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND public.is_activity_member(activity_id, auth.uid())
  AND EXISTS (
        SELECT 1 FROM public.activities a
         WHERE a.id = activity_id
           AND now() >= (date_trunc('day', a.event_datetime AT TIME ZONE 'America/Lima'))
                          AT TIME ZONE 'America/Lima'
      )
);


-- ══ 5. BARRIDO: MARCAR TERMINADOS Y AVISAR ═══════════════════════════

-- Qué avisos ya se mandaron, para no repetirlos.
CREATE TABLE IF NOT EXISTS public.activity_lifecycle_events (
  activity_id uuid        NOT NULL REFERENCES public.activities(id) ON DELETE CASCADE,
  kind        text        NOT NULL CHECK (kind IN ('ended', 'chat_closing', 'chat_closed')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (activity_id, kind)
);

ALTER TABLE public.activity_lifecycle_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.activity_lifecycle_events FROM anon, authenticated;

-- Integrantes de un plan: organizador + participantes.
CREATE OR REPLACE FUNCTION public.activity_member_ids(p_activity_id uuid)
RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT organizer_id FROM public.activities WHERE id = p_activity_id
  UNION
  SELECT user_id FROM public.activity_participants WHERE activity_id = p_activity_id;
$$;

CREATE OR REPLACE FUNCTION public.sweep_activity_lifecycle()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r        record;
  v_count  integer := 0;
BEGIN
  -- 1. Terminados: pasan a 'completed' y se invita a calificar y al mural.
  FOR r IN
    SELECT a.id, a.title, a.organizer_id
      FROM public.activities a
     WHERE a.status = 'active'
       AND now() >= public.activity_ends_at(a.event_datetime, a.duration_minutes)
       AND NOT EXISTS (SELECT 1 FROM public.activity_lifecycle_events e
                        WHERE e.activity_id = a.id AND e.kind = 'ended')
     FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.activities SET status = 'completed' WHERE id = r.id;
    INSERT INTO public.activity_lifecycle_events (activity_id, kind)
    VALUES (r.id, 'ended') ON CONFLICT DO NOTHING;

    INSERT INTO public.notifications (user_id, type, title, body, entity_type, entity_id)
    SELECT m,
           'activity_ended',
           '¿Qué tal estuvo «' || r.title || '»?',
           CASE WHEN m = r.organizer_id
                THEN 'Tu plan terminó. Sube tus fotos al mural de recuerdos; el chat sigue abierto 2 días más.'
                ELSE 'Califica el plan y sube tu foto al mural de recuerdos. El chat sigue abierto 2 días más.'
           END,
           'activity', r.id
      FROM public.activity_member_ids(r.id) AS m;
    v_count := v_count + 1;
  END LOOP;

  -- 2. Falta un día para que cierre el chat: sugerir un clan.
  FOR r IN
    SELECT a.id, a.title
      FROM public.activities a
     WHERE now() >= public.activity_chat_closes_at(a.event_datetime, a.duration_minutes) - interval '1 day'
       AND now() <  public.activity_chat_closes_at(a.event_datetime, a.duration_minutes)
       AND NOT EXISTS (SELECT 1 FROM public.activity_lifecycle_events e
                        WHERE e.activity_id = a.id AND e.kind = 'chat_closing')
  LOOP
    INSERT INTO public.activity_lifecycle_events (activity_id, kind)
    VALUES (r.id, 'chat_closing') ON CONFLICT DO NOTHING;

    INSERT INTO public.notifications (user_id, type, title, body, entity_type, entity_id)
    SELECT m,
           'activity_chat_closing',
           'El chat de «' || r.title || '» se cierra mañana',
           '¿Quieren seguir en contacto? Creen un clan con el grupo desde el chat.',
           'activity', r.id
      FROM public.activity_member_ids(r.id) AS m;
    v_count := v_count + 1;
  END LOOP;

  -- 3. Chat cerrado: sólo se registra (lo bloquea la política del paso 2).
  INSERT INTO public.activity_lifecycle_events (activity_id, kind)
  SELECT a.id, 'chat_closed'
    FROM public.activities a
   WHERE now() >= public.activity_chat_closes_at(a.event_datetime, a.duration_minutes)
  ON CONFLICT DO NOTHING;

  RETURN v_count;
END;
$$;

-- Los planes viejos ya pasados no deben inundar de avisos al aplicar esto:
-- se marcan como avisados sin notificar.
INSERT INTO public.activity_lifecycle_events (activity_id, kind)
SELECT a.id, k.kind
  FROM public.activities a
 CROSS JOIN (VALUES ('ended'), ('chat_closing'), ('chat_closed')) AS k(kind)
 WHERE now() >= public.activity_chat_closes_at(a.event_datetime, a.duration_minutes)
ON CONFLICT DO NOTHING;
UPDATE public.activities a
   SET status = 'completed'
 WHERE a.status = 'active'
   AND now() >= public.activity_chat_closes_at(a.event_datetime, a.duration_minutes);


-- ══ 6. PERMISOS ══════════════════════════════════════════════════════

REVOKE EXECUTE ON FUNCTION public.refresh_organizer_rating(uuid)   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_event_feedback_rating()   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.activity_member_ids(uuid)        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sweep_activity_lifecycle()       FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.my_pending_ratings()             FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.sweep_activity_lifecycle()       TO authenticated;
GRANT  EXECUTE ON FUNCTION public.my_pending_ratings()             TO authenticated;
GRANT  EXECUTE ON FUNCTION public.activity_ends_at(timestamptz, integer)        TO authenticated;
GRANT  EXECUTE ON FUNCTION public.activity_chat_closes_at(timestamptz, integer) TO authenticated;


-- ══ 7. PROGRAMAR EL BARRIDO ══════════════════════════════════════════
-- Cada 10 minutos. Si pg_cron no está disponible (otro entorno), la
-- migración sigue: la app llama al barrido al abrirse.

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'join_activity_lifecycle';
  PERFORM cron.schedule('join_activity_lifecycle', '*/10 * * * *',
                        'SELECT public.sweep_activity_lifecycle()');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron no disponible (%): el barrido lo dispara la app.', SQLERRM;
END;
$$;
