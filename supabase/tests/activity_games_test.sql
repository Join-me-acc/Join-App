-- ════════════════════════════════════════════════════════════════════
--  Pruebas de RLS y reglas de El Impostor sincronizado.
--
--  Se ejecutan dentro de una transacción que se deshace al final, así que
--  no dejan datos en la base local:
--
--    Get-Content supabase/tests/activity_games_test.sql |
--      docker exec -i supabase_db_join psql -U postgres -d postgres -v ON_ERROR_STOP=1
--
--  Actores: organizador (o), dos participantes aceptados (a, b), un tercero
--  (c) que se une después y un usuario externo (x).
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
  IF NOT COALESCE(p_ok, false) THEN
    RAISE EXCEPTION 'FALLÓ: %', p_label;
  END IF;
  RAISE NOTICE 'ok  %', p_label;
END;
$$;

-- ── Datos ─────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role)
VALUES
  ('00000000-0000-0000-0000-0000000000a0', 'org@test.local',  '{"name":"Orga"}',  'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000a1', 'ana@test.local',  '{"name":"Ana"}',   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000a2', 'beto@test.local', '{"name":"Beto"}',  'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000a3', 'caro@test.local', '{"name":"Caro"}',  'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000ff', 'ext@test.local',  '{"name":"Externo"}', 'authenticated', 'authenticated');

INSERT INTO public.activities (id, organizer_id, title, description, category, location_name, event_datetime)
VALUES ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a0',
        'Pichanga de prueba', 'Test', 'Deportes,Fútbol', 'Cancha', now() + interval '1 day');

INSERT INTO public.activity_participants (activity_id, user_id) VALUES
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a2'),
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a3');

CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v uuid);
GRANT ALL ON t_ctx TO authenticated;

SET LOCAL ROLE authenticated;

-- ── 1. El externo no puede crear ni ver salas ─────────────────────────
SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000ff');
DO $$
BEGIN
  PERFORM public.create_or_join_game_session('00000000-0000-0000-0000-00000000aaaa', 'impostor');
  RAISE EXCEPTION 'FALLÓ: el externo creó una sala';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ok  externo no puede crear sala';
END $$;

-- ── 2. El organizador crea, los demás se unen a la misma sala ─────────
SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000a0');
INSERT INTO t_ctx VALUES ('s', public.create_or_join_game_session('00000000-0000-0000-0000-00000000aaaa', 'impostor'));

SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
SELECT pg_temp.check(
  public.create_or_join_game_session('00000000-0000-0000-0000-00000000aaaa', 'impostor') = (SELECT v FROM t_ctx WHERE k = 's'),
  'el participante entra a la sala ya creada');

-- ── 3. Escrituras directas bloqueadas ─────────────────────────────────
DO $$
BEGIN
  UPDATE public.activity_game_sessions SET status = 'finished';
  RAISE EXCEPTION 'FALLÓ: UPDATE directo permitido';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ok  UPDATE directo bloqueado';
END $$;

-- ── 4. Con dos jugadores no se puede iniciar; un participante no host tampoco
DO $$
BEGIN
  PERFORM public.start_impostor_game((SELECT v FROM t_ctx WHERE k = 's'), ARRAY['Pelota']);
  RAISE EXCEPTION 'FALLÓ: un no-host inició la partida';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ok  un participante no host no puede iniciar';
END $$;

SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000a0');
DO $$
BEGIN
  PERFORM public.start_impostor_game((SELECT v FROM t_ctx WHERE k = 's'), ARRAY['Pelota']);
  RAISE EXCEPTION 'FALLÓ: se inició con 2 jugadores';
EXCEPTION WHEN raise_exception THEN
  RAISE NOTICE 'ok  se exigen 3 jugadores';
END $$;

SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
SELECT public.create_or_join_game_session('00000000-0000-0000-0000-00000000aaaa', 'impostor');
SELECT public.set_game_ready((SELECT v FROM t_ctx WHERE k = 's'), true);

-- ── 5. Inicio: roles repartidos, estado público sin secretos ──────────
SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000a0');
SELECT public.start_impostor_game((SELECT v FROM t_ctx WHERE k = 's'),
                                  ARRAY['Pelota', 'Cancha', 'Árbitro'], 60);

SELECT pg_temp.check(
  (SELECT status = 'playing' AND state->>'phase' = 'discussion'
          AND NOT (state ? 'word') AND NOT (state ? 'impostor_id')
     FROM public.activity_game_sessions WHERE id = (SELECT v FROM t_ctx WHERE k = 's')),
  'estado público sin palabra ni impostor');

SELECT pg_temp.check(
  NOT EXISTS (SELECT 1 FROM public.activity_game_events
               WHERE session_id = (SELECT v FROM t_ctx WHERE k = 's')
                 AND (payload ? 'word' OR payload ? 'impostor_id' OR payload ? 'role')),
  'los eventos no filtran secretos');

-- Cada jugador ve exactamente una fila privada: la suya.
SELECT pg_temp.check(
  (SELECT count(*) = 1 AND bool_and(user_id = '00000000-0000-0000-0000-0000000000a0')
     FROM public.activity_game_private_state),
  'el organizador sólo ve su propio rol');

SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
SELECT pg_temp.check(
  (SELECT count(*) = 1 FROM public.activity_game_private_state),
  'la participante sólo ve su propio rol');

-- Quien llega tarde no entra a la partida en curso.
SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
SELECT public.create_or_join_game_session('00000000-0000-0000-0000-00000000aaaa', 'impostor');
SELECT pg_temp.check(
  (SELECT count(*) = 3 FROM public.activity_game_players
    WHERE session_id = (SELECT v FROM t_ctx WHERE k = 's')),
  'nadie se une con la partida empezada');
SELECT pg_temp.check(
  (SELECT count(*) = 0 FROM public.activity_game_private_state),
  'quien no juega no recibe rol');

-- El externo no ve nada.
SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000ff');
SELECT pg_temp.check((SELECT count(*) = 0 FROM public.activity_game_sessions), 'externo no ve sesiones');
SELECT pg_temp.check((SELECT count(*) = 0 FROM public.activity_game_players),  'externo no ve jugadores');
SELECT pg_temp.check((SELECT count(*) = 0 FROM public.activity_game_events),   'externo no ve eventos');

-- ── 6. El impostor nunca recibe la palabra ────────────────────────────
RESET ROLE;
SELECT pg_temp.check(
  (SELECT count(*) = 1 FROM public.activity_game_private_state
    WHERE session_id = (SELECT v FROM t_ctx WHERE k = 's') AND state->>'role' = 'impostor'),
  'hay exactamente un impostor');
SELECT pg_temp.check(
  NOT EXISTS (SELECT 1 FROM public.activity_game_private_state
               WHERE session_id = (SELECT v FROM t_ctx WHERE k = 's')
                 AND state->>'role' = 'impostor' AND state ? 'word'),
  'el impostor no tiene la palabra');
SELECT pg_temp.check(
  (SELECT count(DISTINCT state->>'word') = 1 FROM public.activity_game_private_state
    WHERE session_id = (SELECT v FROM t_ctx WHERE k = 's') AND state->>'role' = 'crew'),
  'todos los demás tienen la misma palabra');

INSERT INTO t_ctx SELECT 'imp', user_id FROM public.activity_game_private_state
 WHERE session_id = (SELECT v FROM t_ctx WHERE k = 's') AND state->>'role' = 'impostor';
SET LOCAL ROLE authenticated;

-- ── 7. Votación: nadie vota antes de tiempo, todos votan al impostor ──
SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  PERFORM public.advance_impostor_to_voting((SELECT v FROM t_ctx WHERE k = 's'));
  RAISE EXCEPTION 'FALLÓ: un participante adelantó la votación';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ok  sólo el host adelanta la votación';
END $$;

SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000a0');
SELECT public.advance_impostor_to_voting((SELECT v FROM t_ctx WHERE k = 's'));

-- Cada uno vota al impostor; el impostor vota a otro.
DO $$
DECLARE
  v_s   uuid := (SELECT v FROM t_ctx WHERE k = 's');
  v_imp uuid := (SELECT v FROM t_ctx WHERE k = 'imp');
  v_p   uuid;
BEGIN
  FOR v_p IN SELECT user_id FROM public.activity_game_players WHERE session_id = v_s ORDER BY display_order LOOP
    PERFORM pg_temp.as_user(v_p);
    IF v_p = v_imp THEN
      PERFORM public.cast_impostor_vote(v_s, (SELECT user_id FROM public.activity_game_players
                                               WHERE session_id = v_s AND user_id <> v_imp LIMIT 1));
    ELSE
      PERFORM public.cast_impostor_vote(v_s, v_imp);
    END IF;
  END LOOP;
END $$;

SELECT pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
SELECT pg_temp.check(
  (SELECT status = 'finished' AND state->'result'->>'winner' = 'group'
          AND state->'result'->>'impostor_id' = (SELECT v FROM t_ctx WHERE k = 'imp')::text
          AND state->'result'->>'word' IN ('Pelota', 'Cancha', 'Árbitro')
     FROM public.activity_game_sessions WHERE id = (SELECT v FROM t_ctx WHERE k = 's')),
  'con todos los votos la ronda se cierra y gana el grupo');

SELECT pg_temp.check(
  (SELECT count(*) = 1 FROM public.activity_game_votes),
  'cada jugador sólo ve su propio voto');

-- ── 8. Revancha con los mismos jugadores ──────────────────────────────
INSERT INTO t_ctx VALUES ('r', public.rematch_game_session((SELECT v FROM t_ctx WHERE k = 's')));
SELECT pg_temp.check(
  (SELECT count(*) = 3 FROM public.activity_game_players WHERE session_id = (SELECT v FROM t_ctx WHERE k = 'r')),
  'la revancha conserva a los jugadores');
SELECT pg_temp.check(
  (SELECT host_user_id = '00000000-0000-0000-0000-0000000000a1' AND status = 'lobby' AND round = 2
     FROM public.activity_game_sessions WHERE id = (SELECT v FROM t_ctx WHERE k = 'r')),
  'quien pide la revancha es el nuevo host');

-- ── 9. Si el host sale del lobby, pasa al siguiente ───────────────────
SELECT public.leave_game_session((SELECT v FROM t_ctx WHERE k = 'r'));
SELECT pg_temp.check(
  (SELECT host_user_id <> '00000000-0000-0000-0000-0000000000a1' AND status = 'lobby'
     FROM public.activity_game_sessions WHERE id = (SELECT v FROM t_ctx WHERE k = 'r')),
  'el host se transfiere al salir');

-- ── 10. Funciones internas cerradas ───────────────────────────────────
DO $$
BEGIN
  PERFORM public._impostor_finish((SELECT v FROM t_ctx WHERE k = 'r'));
  RAISE EXCEPTION 'FALLÓ: se pudo llamar a una función interna';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ok  funciones internas no expuestas';
END $$;

SELECT pg_temp.check(
  (SELECT count(*) = 4 FROM public.get_activity_member_names('00000000-0000-0000-0000-00000000aaaa')),
  'lista de miembros para equipos');

RESET ROLE;
ROLLBACK;
