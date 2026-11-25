-- ════════════════════════════════════════════════════════════════════
--  PARTIDAS SINCRONIZADAS DEL CENTRO DE JUEGOS
--  Migración: 20261124120000_activity_games.sql
--
--  Hasta ahora cada juego vivía en el estado local de un solo teléfono y en
--  El Impostor había que pasarse el celular. Esto añade salas compartidas
--  por actividad: cada participante se une desde su propio teléfono y ve
--  únicamente lo que le corresponde.
--
--  Decisiones que conviene no perder de vista:
--
--   · Toda escritura pasa por RPC SECURITY DEFINER. Las tablas sólo tienen
--     políticas de SELECT: así las reglas del juego (quién puede iniciar,
--     cuándo se vota, cuántos jugadores hacen falta) viven en un solo sitio
--     y no se pueden saltar con la anon key, que viaja dentro del APK.
--
--   · El rol secreto NO está en `activity_game_players`. RLS filtra filas,
--     no columnas: si el rol fuera una columna de la fila del jugador, quien
--     puede ver la sala podría leer el rol de todos. Va en una tabla aparte,
--     `activity_game_private_state`, donde cada quien sólo lee su fila.
--
--   · La palabra secreta y la identidad del impostor no aparecen en el
--     estado público de la sesión ni en los eventos hasta que la ronda
--     termina. Al impostor nunca se le escribe la palabra.
--
--   · Los votos tampoco son públicos: el resto sólo ve cuántos votaron.
--
--   · El resultado lo calcula el servidor. Lo publica en el chat el cliente
--     del host, porque el chat está cifrado de extremo a extremo y el
--     servidor no tiene la clave del grupo (ver 20260807160000).
-- ════════════════════════════════════════════════════════════════════


-- ══ 1. TABLAS ════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.activity_game_sessions (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id   uuid        NOT NULL REFERENCES public.activities(id) ON DELETE CASCADE,
  game_type     text        NOT NULL CHECK (game_type IN ('impostor', 'dice', 'initial')),
  host_user_id  uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status        text        NOT NULL DEFAULT 'lobby'
                CHECK (status IN ('lobby', 'playing', 'finished', 'cancelled')),
  round         integer     NOT NULL DEFAULT 1,
  -- Estado público: fase, cuenta regresiva, conteo de votos y, al terminar,
  -- el resultado. Nunca roles ni palabra mientras se juega.
  state         jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Una sola sala activa por actividad y juego: si dos personas pulsan
-- "Crear sala" a la vez, ambas acaban en la misma.
CREATE UNIQUE INDEX IF NOT EXISTS uq_game_session_active
  ON public.activity_game_sessions (activity_id, game_type)
  WHERE status IN ('lobby', 'playing');

CREATE INDEX IF NOT EXISTS idx_game_sessions_activity
  ON public.activity_game_sessions (activity_id, created_at DESC);


CREATE TABLE IF NOT EXISTS public.activity_game_players (
  session_id     uuid        NOT NULL REFERENCES public.activity_game_sessions(id) ON DELETE CASCADE,
  user_id        uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  display_order  integer     NOT NULL,
  is_ready       boolean     NOT NULL DEFAULT false,
  joined_at      timestamptz NOT NULL DEFAULT now(),
  -- Latido del cliente: la sala muestra quién sigue conectado.
  last_seen_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_game_players_user
  ON public.activity_game_players (user_id);


-- Rol de cada jugador en la ronda. Sólo su dueño puede leerlo.
CREATE TABLE IF NOT EXISTS public.activity_game_private_state (
  session_id  uuid        NOT NULL REFERENCES public.activity_game_sessions(id) ON DELETE CASCADE,
  user_id     uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  round       integer     NOT NULL,
  state       jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, user_id)
);


CREATE TABLE IF NOT EXISTS public.activity_game_votes (
  session_id  uuid        NOT NULL REFERENCES public.activity_game_sessions(id) ON DELETE CASCADE,
  round       integer     NOT NULL,
  voter_id    uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_id   uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, round, voter_id)
);


CREATE TABLE IF NOT EXISTS public.activity_game_events (
  id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  session_id  uuid        NOT NULL REFERENCES public.activity_game_sessions(id) ON DELETE CASCADE,
  user_id     uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  event_type  text        NOT NULL,
  payload     jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_game_events_session
  ON public.activity_game_events (session_id, created_at);


-- updated_at automático en la sesión.
CREATE OR REPLACE FUNCTION public.touch_game_session_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_game_session_updated_at ON public.activity_game_sessions;
CREATE TRIGGER trg_game_session_updated_at
  BEFORE UPDATE ON public.activity_game_sessions
  FOR EACH ROW EXECUTE FUNCTION public.touch_game_session_updated_at();


-- ══ 2. SEGURIDAD (RLS) ═══════════════════════════════════════════════

-- ¿El usuario actual pertenece a la actividad de esta sala?
CREATE OR REPLACE FUNCTION public.can_access_game_session(p_session_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.activity_game_sessions s
     WHERE s.id = p_session_id
       AND public.is_activity_member(s.activity_id, auth.uid())
  );
$$;

ALTER TABLE public.activity_game_sessions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_game_players       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_game_private_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_game_votes         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_game_events        ENABLE ROW LEVEL SECURITY;

-- Las escrituras directas quedan cerradas también a nivel de permisos, no
-- sólo por falta de política: los privilegios por defecto del esquema
-- (20260611040000) conceden INSERT/UPDATE/DELETE a authenticated.
REVOKE INSERT, UPDATE, DELETE ON public.activity_game_sessions      FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.activity_game_players       FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.activity_game_private_state FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.activity_game_votes         FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.activity_game_events        FROM anon, authenticated;
REVOKE ALL ON public.activity_game_sessions, public.activity_game_players,
              public.activity_game_private_state, public.activity_game_votes,
              public.activity_game_events FROM anon;
GRANT SELECT ON public.activity_game_sessions, public.activity_game_players,
                public.activity_game_private_state, public.activity_game_votes,
                public.activity_game_events TO authenticated;

DROP POLICY IF EXISTS "Miembros ven las salas de su actividad" ON public.activity_game_sessions;
CREATE POLICY "Miembros ven las salas de su actividad"
ON public.activity_game_sessions FOR SELECT TO authenticated
USING (public.is_activity_member(activity_id, auth.uid()));

DROP POLICY IF EXISTS "Miembros ven a los jugadores de la sala" ON public.activity_game_players;
CREATE POLICY "Miembros ven a los jugadores de la sala"
ON public.activity_game_players FOR SELECT TO authenticated
USING (public.can_access_game_session(session_id));

DROP POLICY IF EXISTS "Cada jugador ve sólo su rol" ON public.activity_game_private_state;
CREATE POLICY "Cada jugador ve sólo su rol"
ON public.activity_game_private_state FOR SELECT TO authenticated
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Cada jugador ve sólo su voto" ON public.activity_game_votes;
CREATE POLICY "Cada jugador ve sólo su voto"
ON public.activity_game_votes FOR SELECT TO authenticated
USING (voter_id = auth.uid());

DROP POLICY IF EXISTS "Miembros ven los eventos de la sala" ON public.activity_game_events;
CREATE POLICY "Miembros ven los eventos de la sala"
ON public.activity_game_events FOR SELECT TO authenticated
USING (public.can_access_game_session(session_id));


-- ══ 3. FUNCIONES INTERNAS ════════════════════════════════════════════
-- No se exponen a los clientes: se revoca EXECUTE al final.

-- Usuario autenticado o error.
CREATE OR REPLACE FUNCTION public._game_require_user()
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Necesitas iniciar sesión para jugar.' USING ERRCODE = '42501';
  END IF;
  RETURN v_uid;
END;
$$;

-- ¿Puede el usuario administrar la sala? Host u organizador del plan.
CREATE OR REPLACE FUNCTION public._game_can_manage(p_session public.activity_game_sessions, p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p_session.host_user_id = p_user_id
      OR public.is_activity_organizer(p_session.activity_id, p_user_id);
$$;

CREATE OR REPLACE FUNCTION public._game_log(
  p_session_id uuid, p_user_id uuid, p_event text, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  INSERT INTO public.activity_game_events (session_id, user_id, event_type, payload)
  VALUES (p_session_id, p_user_id, p_event, COALESCE(p_payload, '{}'::jsonb));
$$;

-- Añade al usuario a la sala si aún no está. Devuelve true si lo añadió.
CREATE OR REPLACE FUNCTION public._game_add_player(p_session_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_order integer;
BEGIN
  IF EXISTS (SELECT 1 FROM public.activity_game_players
              WHERE session_id = p_session_id AND user_id = p_user_id) THEN
    UPDATE public.activity_game_players SET last_seen_at = now()
     WHERE session_id = p_session_id AND user_id = p_user_id;
    RETURN false;
  END IF;

  IF (SELECT count(*) FROM public.activity_game_players WHERE session_id = p_session_id) >= 12 THEN
    RAISE EXCEPTION 'La sala está llena (máximo 12 jugadores).' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(max(display_order), 0) + 1 INTO v_order
    FROM public.activity_game_players WHERE session_id = p_session_id;

  INSERT INTO public.activity_game_players (session_id, user_id, display_order)
  VALUES (p_session_id, p_user_id, v_order)
  ON CONFLICT (session_id, user_id) DO NOTHING;

  RETURN true;
END;
$$;

-- Cierra la ronda de El Impostor: cuenta votos y escribe el resultado.
-- Se llama con la fila de la sesión ya bloqueada.
CREATE OR REPLACE FUNCTION public._impostor_finish(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_session        public.activity_game_sessions;
  v_impostor_id    uuid;
  v_word           text;
  v_top_target     uuid;
  v_top_votes      integer := 0;
  v_tied           boolean := false;
  v_winner         text;
  v_summary        text;
  v_impostor_name  text;
  v_voted_name     text;
  v_tally          jsonb;
  v_result         jsonb;
  v_players        integer;
BEGIN
  SELECT * INTO v_session FROM public.activity_game_sessions WHERE id = p_session_id;

  SELECT ps.user_id INTO v_impostor_id
    FROM public.activity_game_private_state ps
   WHERE ps.session_id = p_session_id AND ps.state->>'role' = 'impostor'
   LIMIT 1;

  SELECT ps.state->>'word' INTO v_word
    FROM public.activity_game_private_state ps
   WHERE ps.session_id = p_session_id AND ps.state->>'role' = 'crew'
   LIMIT 1;

  SELECT count(*) INTO v_players
    FROM public.activity_game_players WHERE session_id = p_session_id;

  -- Conteo: el más votado y si hay empate en primer lugar.
  WITH tally AS (
    SELECT target_id, count(*)::int AS votes
      FROM public.activity_game_votes
     WHERE session_id = p_session_id AND round = v_session.round
     GROUP BY target_id
  ), ranked AS (
    SELECT target_id, votes, rank() OVER (ORDER BY votes DESC) AS r FROM tally
  )
  SELECT
    (SELECT target_id FROM ranked WHERE r = 1 ORDER BY target_id LIMIT 1),
    COALESCE((SELECT max(votes) FROM ranked), 0),
    (SELECT count(*) FROM ranked WHERE r = 1) > 1,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('user_id', target_id, 'votes', votes)
                               ORDER BY votes DESC) FROM tally), '[]'::jsonb)
  INTO v_top_target, v_top_votes, v_tied, v_tally;

  SELECT display_name INTO v_impostor_name FROM public.profiles WHERE id = v_impostor_id;
  SELECT display_name INTO v_voted_name   FROM public.profiles WHERE id = v_top_target;

  IF v_top_votes = 0 OR v_tied THEN
    v_winner  := 'impostor';
    v_summary := 'El grupo no se puso de acuerdo y ' || COALESCE(v_impostor_name, 'el impostor')
                 || ' escapó sin ser descubierto';
    v_top_target := CASE WHEN v_tied THEN NULL ELSE v_top_target END;
  ELSIF v_top_target = v_impostor_id THEN
    v_winner  := 'group';
    v_summary := 'El grupo descubrió a ' || COALESCE(v_impostor_name, 'el impostor');
  ELSE
    v_winner  := 'impostor';
    v_summary := 'El grupo acusó a ' || COALESCE(v_voted_name, 'alguien')
                 || ' y ' || COALESCE(v_impostor_name, 'el impostor') || ' se salió con la suya';
  END IF;

  v_result := jsonb_build_object(
    'winner',          v_winner,
    'summary',         v_summary,
    'impostor_id',     v_impostor_id,
    'impostor_name',   v_impostor_name,
    'word',            v_word,
    'most_voted_id',   v_top_target,
    'tie',             v_tied,
    'tally',           v_tally,
    'participants',    v_players
  );

  UPDATE public.activity_game_sessions
     SET status = 'finished',
         state  = jsonb_build_object(
                    'phase',        'result',
                    'player_count', v_players,
                    'votes_count',  (SELECT count(*) FROM public.activity_game_votes
                                      WHERE session_id = p_session_id AND round = v_session.round),
                    'finished_at',  now(),
                    'result',       v_result)
   WHERE id = p_session_id;

  -- El evento lleva sólo el desenlace, sin el detalle de votos.
  PERFORM public._game_log(p_session_id, NULL, 'finished',
                           jsonb_build_object('winner', v_winner));

  RETURN v_result;
END;
$$;


-- ══ 4. RPC PÚBLICAS ══════════════════════════════════════════════════

-- Crea la sala del juego o devuelve la que ya está activa, y une al usuario
-- si todavía está en el lobby.
CREATE OR REPLACE FUNCTION public.create_or_join_game_session(
  p_activity_id uuid, p_game_type text DEFAULT 'impostor')
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid     uuid := public._game_require_user();
  v_session public.activity_game_sessions;
BEGIN
  IF NOT public.is_activity_member(p_activity_id, v_uid) THEN
    RAISE EXCEPTION 'Sólo los participantes del plan pueden jugar.' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.activity_game_sessions (activity_id, game_type, host_user_id)
  VALUES (p_activity_id, p_game_type, v_uid)
  ON CONFLICT (activity_id, game_type) WHERE status IN ('lobby', 'playing') DO NOTHING
  RETURNING * INTO v_session;

  IF v_session.id IS NOT NULL THEN
    PERFORM public._game_log(v_session.id, v_uid, 'created');
  ELSE
    SELECT * INTO v_session FROM public.activity_game_sessions
     WHERE activity_id = p_activity_id AND game_type = p_game_type
       AND status IN ('lobby', 'playing')
     FOR UPDATE;
  END IF;

  -- Con la partida empezada no se entra: el reparto ya está hecho. Quien ya
  -- era jugador vuelve a su sitio.
  IF v_session.status = 'lobby' THEN
    IF public._game_add_player(v_session.id, v_uid) THEN
      PERFORM public._game_log(v_session.id, v_uid, 'joined');
    END IF;
  ELSE
    UPDATE public.activity_game_players SET last_seen_at = now()
     WHERE session_id = v_session.id AND user_id = v_uid;
  END IF;

  RETURN v_session.id;
END;
$$;


-- Sale del lobby. Si sale el host, la sala pasa al siguiente; si queda
-- vacía, se cancela. Durante la partida no se borra al jugador: cerrar la
-- pantalla no debe romper el reparto de roles.
CREATE OR REPLACE FUNCTION public.leave_game_session(p_session_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid      uuid := public._game_require_user();
  v_session  public.activity_game_sessions;
  v_next     uuid;
BEGIN
  SELECT * INTO v_session FROM public.activity_game_sessions
   WHERE id = p_session_id FOR UPDATE;
  IF v_session.id IS NULL OR v_session.status <> 'lobby' THEN
    RETURN;
  END IF;

  DELETE FROM public.activity_game_players
   WHERE session_id = p_session_id AND user_id = v_uid;
  IF NOT FOUND THEN RETURN; END IF;

  PERFORM public._game_log(p_session_id, v_uid, 'left');

  IF v_session.host_user_id = v_uid THEN
    SELECT user_id INTO v_next FROM public.activity_game_players
     WHERE session_id = p_session_id ORDER BY display_order LIMIT 1;
    IF v_next IS NULL THEN
      UPDATE public.activity_game_sessions SET status = 'cancelled' WHERE id = p_session_id;
      PERFORM public._game_log(p_session_id, v_uid, 'cancelled');
    ELSE
      UPDATE public.activity_game_sessions SET host_user_id = v_next WHERE id = p_session_id;
      PERFORM public._game_log(p_session_id, v_next, 'host_changed');
    END IF;
  END IF;
END;
$$;


CREATE OR REPLACE FUNCTION public.set_game_ready(p_session_id uuid, p_ready boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := public._game_require_user();
BEGIN
  UPDATE public.activity_game_players p
     SET is_ready = p_ready, last_seen_at = now()
    FROM public.activity_game_sessions s
   WHERE p.session_id = p_session_id AND p.user_id = v_uid
     AND s.id = p.session_id AND s.status = 'lobby';
END;
$$;


-- Latido: lo envía cada cliente mientras tiene la sala abierta.
CREATE OR REPLACE FUNCTION public.touch_game_presence(p_session_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := public._game_require_user();
BEGIN
  UPDATE public.activity_game_players SET last_seen_at = now()
   WHERE session_id = p_session_id AND user_id = v_uid;
END;
$$;


-- Reparte roles de forma atómica. El host envía las palabras candidatas del
-- catálogo de la categoría y el servidor elige una al azar: ni siquiera el
-- host sabe cuál tocó ni quién es el impostor.
CREATE OR REPLACE FUNCTION public.start_impostor_game(
  p_session_id uuid, p_words text[], p_discussion_seconds integer DEFAULT 180)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid       uuid := public._game_require_user();
  v_session   public.activity_game_sessions;
  v_words     text[];
  v_word      text;
  v_impostor  uuid;
  v_starter   uuid;
  v_players   integer;
  v_seconds   integer := LEAST(GREATEST(COALESCE(p_discussion_seconds, 180), 60), 600);
BEGIN
  SELECT * INTO v_session FROM public.activity_game_sessions
   WHERE id = p_session_id FOR UPDATE;

  IF v_session.id IS NULL OR v_session.game_type <> 'impostor' THEN
    RAISE EXCEPTION 'La sala no existe.' USING ERRCODE = 'P0002';
  END IF;
  IF NOT public._game_can_manage(v_session, v_uid) THEN
    RAISE EXCEPTION 'Sólo el host o el organizador puede iniciar la partida.' USING ERRCODE = '42501';
  END IF;
  IF v_session.status <> 'lobby' THEN
    RAISE EXCEPTION 'La partida ya empezó.' USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*) INTO v_players FROM public.activity_game_players WHERE session_id = p_session_id;
  IF v_players < 3 THEN
    RAISE EXCEPTION 'Se necesitan al menos 3 jugadores.' USING ERRCODE = 'P0001';
  END IF;

  SELECT array_agg(DISTINCT left(btrim(w), 60)) INTO v_words
    FROM unnest(COALESCE(p_words, ARRAY[]::text[])) AS w
   WHERE btrim(w) <> '';
  IF v_words IS NULL OR cardinality(v_words) = 0 THEN
    RAISE EXCEPTION 'Faltan palabras para la ronda.' USING ERRCODE = '22023';
  END IF;
  IF cardinality(v_words) > 300 THEN
    v_words := v_words[1:300];
  END IF;

  v_word := v_words[1 + floor(random() * cardinality(v_words))::int];

  SELECT user_id INTO v_impostor FROM public.activity_game_players
   WHERE session_id = p_session_id ORDER BY random() LIMIT 1;
  SELECT user_id INTO v_starter FROM public.activity_game_players
   WHERE session_id = p_session_id ORDER BY random() LIMIT 1;

  DELETE FROM public.activity_game_private_state WHERE session_id = p_session_id;
  DELETE FROM public.activity_game_votes WHERE session_id = p_session_id;

  INSERT INTO public.activity_game_private_state (session_id, user_id, round, state)
  SELECT p_session_id, p.user_id, v_session.round,
         CASE WHEN p.user_id = v_impostor
              THEN jsonb_build_object('role', 'impostor')
              ELSE jsonb_build_object('role', 'crew', 'word', v_word) END
    FROM public.activity_game_players p
   WHERE p.session_id = p_session_id;

  UPDATE public.activity_game_sessions
     SET status = 'playing',
         state  = jsonb_build_object(
                    'phase',              'discussion',
                    'started_at',         now(),
                    'discussion_ends_at', now() + make_interval(secs => v_seconds),
                    'discussion_seconds', v_seconds,
                    'starter_id',         v_starter,
                    'player_count',       v_players,
                    'votes_count',        0)
   WHERE id = p_session_id;

  PERFORM public._game_log(p_session_id, v_uid, 'started',
                           jsonb_build_object('players', v_players));
END;
$$;


-- Pasa de la discusión a la votación. El host puede hacerlo cuando quiera;
-- cualquier jugador, cuando se acabó el tiempo (por si el host se fue).
CREATE OR REPLACE FUNCTION public.advance_impostor_to_voting(p_session_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid      uuid := public._game_require_user();
  v_session  public.activity_game_sessions;
  v_is_player boolean;
BEGIN
  SELECT * INTO v_session FROM public.activity_game_sessions
   WHERE id = p_session_id FOR UPDATE;

  IF v_session.id IS NULL OR v_session.status <> 'playing'
     OR v_session.state->>'phase' <> 'discussion' THEN
    RETURN;
  END IF;

  v_is_player := EXISTS (SELECT 1 FROM public.activity_game_players
                          WHERE session_id = p_session_id AND user_id = v_uid);

  IF NOT (public._game_can_manage(v_session, v_uid)
          OR (v_is_player AND (v_session.state->>'discussion_ends_at')::timestamptz <= now())) THEN
    RAISE EXCEPTION 'Sólo el host puede adelantar la votación.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.activity_game_sessions
     SET state = state || jsonb_build_object('phase', 'voting', 'voting_started_at', now())
   WHERE id = p_session_id;

  PERFORM public._game_log(p_session_id, v_uid, 'voting_started');
END;
$$;


-- Voto secreto. Se puede cambiar mientras dure la votación. Cuando han
-- votado todos, la ronda se cierra sola.
CREATE OR REPLACE FUNCTION public.cast_impostor_vote(p_session_id uuid, p_target_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid      uuid := public._game_require_user();
  v_session  public.activity_game_sessions;
  v_votes    integer;
  v_players  integer;
BEGIN
  SELECT * INTO v_session FROM public.activity_game_sessions
   WHERE id = p_session_id FOR UPDATE;

  IF v_session.id IS NULL OR v_session.status <> 'playing'
     OR v_session.state->>'phase' <> 'voting' THEN
    RAISE EXCEPTION 'La votación no está abierta.' USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.activity_game_players
                  WHERE session_id = p_session_id AND user_id = v_uid) THEN
    RAISE EXCEPTION 'No estás en esta partida.' USING ERRCODE = '42501';
  END IF;
  IF p_target_id = v_uid THEN
    RAISE EXCEPTION 'No puedes votar por ti.' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.activity_game_players
                  WHERE session_id = p_session_id AND user_id = p_target_id) THEN
    RAISE EXCEPTION 'Esa persona no está jugando.' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.activity_game_votes (session_id, round, voter_id, target_id)
  VALUES (p_session_id, v_session.round, v_uid, p_target_id)
  ON CONFLICT (session_id, round, voter_id)
  DO UPDATE SET target_id = EXCLUDED.target_id, created_at = now();

  SELECT count(*) INTO v_votes FROM public.activity_game_votes
   WHERE session_id = p_session_id AND round = v_session.round;
  SELECT count(*) INTO v_players FROM public.activity_game_players
   WHERE session_id = p_session_id;

  UPDATE public.activity_game_sessions
     SET state = state || jsonb_build_object('votes_count', v_votes)
   WHERE id = p_session_id;

  -- Sin el destino: nadie debe poder deducir votos leyendo eventos.
  PERFORM public._game_log(p_session_id, v_uid, 'vote_cast');

  IF v_votes >= v_players THEN
    PERFORM public._impostor_finish(p_session_id);
  END IF;
END;
$$;


-- Cierra la votación aunque falten votos (alguien se quedó sin batería).
CREATE OR REPLACE FUNCTION public.finish_impostor_game(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid      uuid := public._game_require_user();
  v_session  public.activity_game_sessions;
BEGIN
  SELECT * INTO v_session FROM public.activity_game_sessions
   WHERE id = p_session_id FOR UPDATE;

  IF v_session.id IS NULL OR v_session.status <> 'playing' THEN
    RETURN v_session.state->'result';
  END IF;
  IF NOT public._game_can_manage(v_session, v_uid) THEN
    RAISE EXCEPTION 'Sólo el host puede cerrar la votación.' USING ERRCODE = '42501';
  END IF;

  RETURN public._impostor_finish(p_session_id);
END;
$$;


CREATE OR REPLACE FUNCTION public.cancel_game_session(p_session_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid      uuid := public._game_require_user();
  v_session  public.activity_game_sessions;
BEGIN
  SELECT * INTO v_session FROM public.activity_game_sessions
   WHERE id = p_session_id FOR UPDATE;
  IF v_session.id IS NULL OR v_session.status NOT IN ('lobby', 'playing') THEN
    RETURN;
  END IF;
  IF NOT public._game_can_manage(v_session, v_uid) THEN
    RAISE EXCEPTION 'Sólo el host o el organizador puede cancelar la partida.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.activity_game_sessions SET status = 'cancelled' WHERE id = p_session_id;
  PERFORM public._game_log(p_session_id, v_uid, 'cancelled');
END;
$$;


-- Revancha: abre una sala nueva con los mismos jugadores (sin "listo").
-- Si ya hay una sala activa para el plan, devuelve esa.
CREATE OR REPLACE FUNCTION public.rematch_game_session(p_session_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid      uuid := public._game_require_user();
  v_old      public.activity_game_sessions;
  v_new      public.activity_game_sessions;
BEGIN
  SELECT * INTO v_old FROM public.activity_game_sessions WHERE id = p_session_id;
  IF v_old.id IS NULL OR NOT public.is_activity_member(v_old.activity_id, v_uid) THEN
    RAISE EXCEPTION 'La sala no existe.' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.activity_game_sessions (activity_id, game_type, host_user_id, round)
  VALUES (v_old.activity_id, v_old.game_type, v_uid, v_old.round + 1)
  ON CONFLICT (activity_id, game_type) WHERE status IN ('lobby', 'playing') DO NOTHING
  RETURNING * INTO v_new;

  IF v_new.id IS NULL THEN
    -- Otro jugador pidió la revancha primero: nos unimos a la suya.
    RETURN public.create_or_join_game_session(v_old.activity_id, v_old.game_type);
  END IF;

  INSERT INTO public.activity_game_players (session_id, user_id, display_order)
  SELECT v_new.id, p.user_id, p.display_order
    FROM public.activity_game_players p
   WHERE p.session_id = p_session_id
     AND public.is_activity_member(v_old.activity_id, p.user_id);

  PERFORM public._game_add_player(v_new.id, v_uid);
  PERFORM public._game_log(v_new.id, v_uid, 'rematch',
                           jsonb_build_object('previous_session_id', p_session_id));
  RETURN v_new.id;
END;
$$;


-- Quién comparte el plan: lo usa el armador de equipos y el bracket.
CREATE OR REPLACE FUNCTION public.get_activity_member_names(p_activity_id uuid)
RETURNS TABLE (user_id uuid, display_name text, profile_image_url text, is_organizer boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_activity_member(p_activity_id, auth.uid()) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT p.id, p.display_name::text, p.profile_image_url::text, true
    FROM public.activities a JOIN public.profiles p ON p.id = a.organizer_id
   WHERE a.id = p_activity_id
  UNION
  SELECT p.id, p.display_name::text, p.profile_image_url::text, false
    FROM public.activity_participants ap JOIN public.profiles p ON p.id = ap.user_id
   WHERE ap.activity_id = p_activity_id
     AND ap.user_id <> (SELECT organizer_id FROM public.activities WHERE id = p_activity_id);
END;
$$;


-- ══ 5. PERMISOS DE EJECUCIÓN ═════════════════════════════════════════
-- Los privilegios por defecto del esquema dan EXECUTE a anon y
-- authenticated sobre toda función nueva. Las internas se cierran.

REVOKE EXECUTE ON FUNCTION public._game_require_user()                               FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._game_can_manage(public.activity_game_sessions, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._game_log(uuid, uuid, text, jsonb)                 FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._game_add_player(uuid, uuid)                       FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._impostor_finish(uuid)                             FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.create_or_join_game_session(uuid, text)        FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.leave_game_session(uuid)                        FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_game_ready(uuid, boolean)                   FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.touch_game_presence(uuid)                       FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.start_impostor_game(uuid, text[], integer)      FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.advance_impostor_to_voting(uuid)                FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cast_impostor_vote(uuid, uuid)                  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.finish_impostor_game(uuid)                      FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cancel_game_session(uuid)                       FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.rematch_game_session(uuid)                      FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_activity_member_names(uuid)                 FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_or_join_game_session(uuid, text)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_game_session(uuid)                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_game_ready(uuid, boolean)              TO authenticated;
GRANT EXECUTE ON FUNCTION public.touch_game_presence(uuid)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_impostor_game(uuid, text[], integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.advance_impostor_to_voting(uuid)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.cast_impostor_vote(uuid, uuid)             TO authenticated;
GRANT EXECUTE ON FUNCTION public.finish_impostor_game(uuid)                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_game_session(uuid)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.rematch_game_session(uuid)                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_activity_member_names(uuid)            TO authenticated;


-- ══ 6. REALTIME ══════════════════════════════════════════════════════
-- Realtime respeta RLS: cada suscriptor recibe sólo las filas que puede
-- leer, así que su rol privado le llega a él y a nadie más.

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['activity_game_sessions', 'activity_game_players',
                           'activity_game_private_state', 'activity_game_events']
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
                      AND tablename = t) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END;
$$;


-- ══ 7. CHAT: NOTIFICACIÓN DEL RESULTADO ══════════════════════════════
-- El resultado llega al chat como mensaje cifrado de tipo 'game_result'.
-- La notificación no puede leer su contenido, así que dice qué es sin
-- revelar nada.

CREATE OR REPLACE FUNCTION public.handle_new_chat_message()
RETURNS TRIGGER AS $$
DECLARE
  v_sender_name TEXT;
BEGIN
  SELECT display_name INTO v_sender_name
  FROM public.profiles WHERE id = NEW.user_id;

  INSERT INTO public.notifications (user_id, type, title, body, entity_type, entity_id)
  SELECT m.user_id,
         'new_message',
         'Nuevo mensaje de ' || COALESCE(v_sender_name, 'Alguien'),
         CASE WHEN NEW.type = 'image'       THEN '📷 Envió una imagen'
              WHEN NEW.type = 'game_result' THEN '🎲 Compartió el resultado de una partida'
              ELSE '💬 Envió un mensaje nuevo en el grupo.' END,
         'activity',
         NEW.activity_id
  FROM (
    SELECT jr.user_id
    FROM public.join_requests jr
    WHERE jr.activity_id = NEW.activity_id AND jr.status = 'accepted'
    UNION
    SELECT a.organizer_id
    FROM public.activities a
    WHERE a.id = NEW.activity_id
  ) m
  WHERE m.user_id <> NEW.user_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
