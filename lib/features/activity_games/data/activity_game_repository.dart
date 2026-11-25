import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity_game_models.dart';

/// Acceso a las partidas sincronizadas.
///
/// Toda escritura va por RPC: las tablas sólo admiten lectura desde el
/// cliente (ver la migración 20261124120000_activity_games.sql). Las
/// lecturas pasan por RLS, así que [fetchMyRole] devuelve únicamente el rol
/// del usuario autenticado aunque la consulta no filtre por él.
class ActivityGameRepository {
  final SupabaseClient _supabase;

  ActivityGameRepository({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  static const _sessionSelect = '''
    id, activity_id, game_type, host_user_id, status, round, state, updated_at,
    players:activity_game_players(
      user_id, display_order, is_ready, last_seen_at,
      profile:profiles(display_name, profile_image_url)
    )
  ''';

  // ── Lectura ───────────────────────────────────────────────────

  Future<GameSession?> fetchSession(String sessionId) async {
    final row = await _supabase
        .from('activity_game_sessions')
        .select(_sessionSelect)
        .eq('id', sessionId)
        .maybeSingle();
    return row == null ? null : GameSession.fromJson(row);
  }

  /// Sala en curso del plan, para ofrecer volver a ella.
  Future<GameSession?> fetchActiveSession(
    String activityId, {
    String gameType = 'impostor',
  }) async {
    final row = await _supabase
        .from('activity_game_sessions')
        .select(_sessionSelect)
        .eq('activity_id', activityId)
        .eq('game_type', gameType)
        .inFilter('status', ['lobby', 'playing'])
        .maybeSingle();
    return row == null ? null : GameSession.fromJson(row);
  }

  Future<ImpostorRole?> fetchMyRole(String sessionId) async {
    final userId = currentUserId;
    if (userId == null) return null;
    final row = await _supabase
        .from('activity_game_private_state')
        .select('round, state')
        .eq('session_id', sessionId)
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : ImpostorRole.fromJson(row);
  }

  /// A quién votó el usuario en la ronda. RLS sólo deja ver el voto propio.
  Future<String?> fetchMyVote(String sessionId, int round) async {
    final userId = currentUserId;
    if (userId == null) return null;
    final row = await _supabase
        .from('activity_game_votes')
        .select('target_id')
        .eq('session_id', sessionId)
        .eq('round', round)
        .eq('voter_id', userId)
        .maybeSingle();
    return row?['target_id'] as String?;
  }

  Future<List<ActivityMember>> fetchMembers(String activityId) async {
    final rows = await _supabase.rpc(
      'get_activity_member_names',
      params: {'p_activity_id': activityId},
    );
    return [
      for (final row in (rows as List? ?? const []))
        ActivityMember.fromJson(row as Map<String, dynamic>),
    ];
  }

  // ── Escritura (RPC) ───────────────────────────────────────────

  Future<String> createOrJoin(String activityId,
      {String gameType = 'impostor'}) async {
    final id = await _supabase.rpc('create_or_join_game_session', params: {
      'p_activity_id': activityId,
      'p_game_type': gameType,
    });
    return id as String;
  }

  Future<void> leave(String sessionId) =>
      _supabase.rpc('leave_game_session', params: {'p_session_id': sessionId});

  Future<void> setReady(String sessionId, bool ready) => _supabase.rpc(
        'set_game_ready',
        params: {'p_session_id': sessionId, 'p_ready': ready},
      );

  Future<void> heartbeat(String sessionId) =>
      _supabase.rpc('touch_game_presence', params: {'p_session_id': sessionId});

  /// [words] son las candidatas del catálogo de la categoría; el servidor
  /// elige una sin decírsela a nadie, host incluido.
  Future<void> startImpostor(
    String sessionId, {
    required List<String> words,
    int discussionSeconds = 180,
  }) =>
      _supabase.rpc('start_impostor_game', params: {
        'p_session_id': sessionId,
        'p_words': words,
        'p_discussion_seconds': discussionSeconds,
      });

  Future<void> advanceToVoting(String sessionId) => _supabase.rpc(
        'advance_impostor_to_voting',
        params: {'p_session_id': sessionId},
      );

  Future<void> vote(String sessionId, String targetId) => _supabase.rpc(
        'cast_impostor_vote',
        params: {'p_session_id': sessionId, 'p_target_id': targetId},
      );

  Future<void> finish(String sessionId) => _supabase
      .rpc('finish_impostor_game', params: {'p_session_id': sessionId});

  Future<void> cancel(String sessionId) =>
      _supabase.rpc('cancel_game_session', params: {'p_session_id': sessionId});

  Future<String> rematch(String sessionId) async {
    final id = await _supabase
        .rpc('rematch_game_session', params: {'p_session_id': sessionId});
    return id as String;
  }

  // ── Realtime ──────────────────────────────────────────────────

  /// Avisa de cualquier cambio en la sala. El cliente vuelve a leer la
  /// sesión completa en lugar de aplicar cada cambio: es más simple y
  /// resiste eventos perdidos durante una reconexión.
  ///
  /// Realtime no filtra los DELETE por columna, así que la salida de un
  /// jugador se detecta por el evento 'left' de `activity_game_events`.
  ///
  /// Devuelve la función que cancela la suscripción.
  Future<void> Function() subscribe(
      String sessionId, void Function() onChange) {
    PostgresChangeFilter bySession(String column) => PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: column,
          value: sessionId,
        );

    final channel = _supabase
        .channel('game-session-$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'activity_game_sessions',
          filter: bySession('id'),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'activity_game_players',
          filter: bySession('session_id'),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'activity_game_events',
          filter: bySession('session_id'),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'activity_game_private_state',
          filter: bySession('session_id'),
          callback: (_) => onChange(),
        )
        .subscribe();
    return () => _supabase.removeChannel(channel);
  }
}

/// Mensaje legible para el usuario a partir de un error de RPC.
///
/// Las funciones de la base lanzan sus errores ya redactados en español;
/// el resto se resume para no mostrar trazas técnicas.
String friendlyGameError(Object error) {
  if (error is PostgrestException) {
    final message = error.message.trim();
    if (message.isNotEmpty && !message.contains('function') &&
        !message.contains('relation')) {
      return message;
    }
  }
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('ClientException')) {
    return 'Sin conexión. Reintentando…';
  }
  return 'Algo salió mal. Inténtalo de nuevo.';
}
