-- ════════════════════════════════════════════════════════════════════
--  Pruebas del ciclo de vida de un plan (se deshacen al terminar):
--
--    Get-Content supabase/tests/activity_lifecycle_test.sql |
--      docker exec -i supabase_db_join psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q
--
--  Planes: «ayer» (terminado, chat en gracia), «hace 5 días» (chat
--  cerrado) y «mañana» (no empezó).
-- ════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_id uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', p_id::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.check(p_ok boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(p_ok, false) THEN RAISE EXCEPTION 'FALLÓ: %', p_label; END IF;
  RAISE NOTICE 'ok  %', p_label;
END;
$$;

INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role) VALUES
  ('00000000-0000-0000-0000-0000000000b0', 'orga2@test.local', '{"name":"Orga"}', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b1', 'part2@test.local', '{"name":"Part"}', 'authenticated', 'authenticated');

-- Las horas se fijan a mediodía de Lima para no depender de la hora a la
-- que corra la prueba.
INSERT INTO public.activities (id, organizer_id, title, description, location_name, event_datetime, duration_minutes)
VALUES
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b0', 'Ayer', 'x', 'x',
   ((date_trunc('day', now() AT TIME ZONE 'America/Lima') - interval '1 day' + interval '12 hours') AT TIME ZONE 'America/Lima'), 120),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000b0', 'Hace 5 días', 'x', 'x',
   ((date_trunc('day', now() AT TIME ZONE 'America/Lima') - interval '5 days' + interval '12 hours') AT TIME ZONE 'America/Lima'), 120),
  ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000b0', 'Mañana', 'x', 'x',
   ((date_trunc('day', now() AT TIME ZONE 'America/Lima') + interval '1 day' + interval '12 hours') AT TIME ZONE 'America/Lima'), 120);

INSERT INTO public.activity_participants (activity_id, user_id) VALUES
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000b1');

-- ── Fechas ────────────────────────────────────────────────────────────
SELECT pg_temp.check(public.activity_has_ended('00000000-0000-0000-0000-0000000000c1'), 'el de ayer terminó');
SELECT pg_temp.check(NOT public.activity_has_ended('00000000-0000-0000-0000-0000000000c3'), 'el de mañana no terminó');
SELECT pg_temp.check(public.activity_chat_is_open('00000000-0000-0000-0000-0000000000c1'), 'chat de ayer sigue abierto (2 días de gracia)');
SELECT pg_temp.check(NOT public.activity_chat_is_open('00000000-0000-0000-0000-0000000000c2'), 'chat de hace 5 días cerrado');

-- ── Barrido ───────────────────────────────────────────────────────────
SELECT public.sweep_activity_lifecycle();
SELECT pg_temp.check(
  (SELECT status = 'completed' FROM public.activities WHERE id = '00000000-0000-0000-0000-0000000000c1'),
  'el barrido marca completed');
SELECT pg_temp.check(
  (SELECT status = 'active' FROM public.activities WHERE id = '00000000-0000-0000-0000-0000000000c3'),
  'el barrido no toca los que no terminaron');
SELECT pg_temp.check(
  (SELECT count(*) = 2 FROM public.notifications
    WHERE entity_id = '00000000-0000-0000-0000-0000000000c1' AND type = 'activity_ended'),
  'avisa a organizador y participante');
SELECT public.sweep_activity_lifecycle();
SELECT pg_temp.check(
  (SELECT count(*) = 2 FROM public.notifications
    WHERE entity_id = '00000000-0000-0000-0000-0000000000c1' AND type = 'activity_ended'),
  'el barrido no repite avisos');

SET LOCAL ROLE authenticated;

-- ── Chat ──────────────────────────────────────────────────────────────
SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
INSERT INTO public.chat_messages (activity_id, user_id, message)
VALUES ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1', 'chau');
SELECT pg_temp.check(true, 'se escribe durante los 2 días de gracia');

DO $$
BEGIN
  INSERT INTO public.chat_messages (activity_id, user_id, message)
  VALUES ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000b1', 'tarde');
  RAISE EXCEPTION 'FALLÓ: se escribió en un chat cerrado';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ok  el chat cerrado no acepta mensajes';
END $$;

SELECT pg_temp.check(
  (SELECT count(*) >= 1 FROM public.chat_messages WHERE activity_id = '00000000-0000-0000-0000-0000000000c1'),
  'el chat se sigue pudiendo leer');

-- ── Calificaciones ────────────────────────────────────────────────────
SELECT pg_temp.check(
  (SELECT count(*) = 2 FROM public.my_pending_ratings()),
  'pendientes de calificar: los dos terminados');

DO $$
BEGIN
  INSERT INTO public.event_feedback (activity_id, user_id, group_rating, attendance_score)
  VALUES ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000b1', 5, 5);
  RAISE EXCEPTION 'FALLÓ: se calificó un plan que no terminó';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ok  no se califica antes de terminar';
END $$;

INSERT INTO public.event_feedback (activity_id, user_id, group_rating, attendance_score)
VALUES ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1', 4, 5);
INSERT INTO public.event_feedback (activity_id, user_id, group_rating, attendance_score)
VALUES ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000b1', 5, 5);

SELECT pg_temp.check(
  (SELECT rating = 4.5 AND rating_count = 2 FROM public.profiles WHERE id = '00000000-0000-0000-0000-0000000000b0'),
  'la nota del organizador es el promedio');
SELECT pg_temp.check(
  (SELECT count(*) = 0 FROM public.my_pending_ratings()),
  'ya no quedan pendientes');

SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000b0');
DO $$
BEGIN
  INSERT INTO public.event_feedback (activity_id, user_id, group_rating, attendance_score)
  VALUES ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b0', 5, 5);
  RAISE EXCEPTION 'FALLÓ: el organizador calificó su propio plan';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ok  el organizador no califica su propio plan';
END $$;

-- ── Mural ─────────────────────────────────────────────────────────────
INSERT INTO public.event_photos (activity_id, user_id, photo_url)
VALUES ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b0', 'x/foto.jpg');
SELECT pg_temp.check(true, 'se suben fotos al mural después del plan');

DO $$
BEGIN
  INSERT INTO public.event_photos (activity_id, user_id, photo_url)
  VALUES ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000b0', 'x/foto.jpg');
  RAISE EXCEPTION 'FALLÓ: foto antes del día del plan';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ok  no hay recuerdos antes del día del plan';
END $$;

RESET ROLE;
ROLLBACK;
