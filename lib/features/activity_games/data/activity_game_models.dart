/// Modelos de las partidas sincronizadas del centro de juegos.
///
/// Reflejan las tablas de la migración 20261124120000_activity_games.sql.
/// Ninguno guarda el rol de otro jugador: el único estado privado que llega
/// al cliente es el del usuario autenticado ([ImpostorRole]).
library;

enum GameSessionStatus { lobby, playing, finished, cancelled }

enum ImpostorPhase { lobby, discussion, voting, result }

GameSessionStatus _statusFrom(String? value) => switch (value) {
      'playing' => GameSessionStatus.playing,
      'finished' => GameSessionStatus.finished,
      'cancelled' => GameSessionStatus.cancelled,
      _ => GameSessionStatus.lobby,
    };

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

int _int(Object? value, [int fallback = 0]) => switch (value) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v) ?? fallback,
      _ => fallback,
    };

class GamePlayer {
  final String userId;
  final String displayName;
  final String imageUrl;
  final int displayOrder;
  final bool isReady;
  final DateTime? lastSeenAt;

  const GamePlayer({
    required this.userId,
    required this.displayName,
    this.imageUrl = '',
    this.displayOrder = 0,
    this.isReady = false,
    this.lastSeenAt,
  });

  /// Conectado si dio señales de vida hace poco. Los clientes mandan un
  /// latido cada 20 s mientras tienen la sala abierta.
  bool isOnline(DateTime now) =>
      lastSeenAt != null && now.difference(lastSeenAt!).inSeconds < 50;

  factory GamePlayer.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>? ?? const {};
    return GamePlayer(
      userId: json['user_id'] as String,
      displayName: (profile['display_name'] as String?)?.trim().isNotEmpty == true
          ? profile['display_name'] as String
          : 'Jugador',
      imageUrl: (profile['profile_image_url'] as String?) ?? '',
      displayOrder: _int(json['display_order']),
      isReady: json['is_ready'] == true,
      lastSeenAt: _date(json['last_seen_at']),
    );
  }
}

/// Resultado de una ronda de El Impostor, calculado en el servidor.
class ImpostorResult {
  /// 'group' o 'impostor'.
  final String winner;
  final String summary;
  final String? impostorId;
  final String? impostorName;
  final String? word;
  final String? mostVotedId;
  final bool tie;
  final Map<String, int> tally;
  final int participants;

  const ImpostorResult({
    required this.winner,
    required this.summary,
    this.impostorId,
    this.impostorName,
    this.word,
    this.mostVotedId,
    this.tie = false,
    this.tally = const {},
    this.participants = 0,
  });

  bool get groupWon => winner == 'group';

  factory ImpostorResult.fromJson(Map<String, dynamic> json) {
    final tally = <String, int>{};
    for (final entry in (json['tally'] as List? ?? const [])) {
      if (entry is Map && entry['user_id'] is String) {
        tally[entry['user_id'] as String] = _int(entry['votes']);
      }
    }
    return ImpostorResult(
      winner: (json['winner'] as String?) ?? 'impostor',
      summary: (json['summary'] as String?) ?? '',
      impostorId: json['impostor_id'] as String?,
      impostorName: json['impostor_name'] as String?,
      word: json['word'] as String?,
      mostVotedId: json['most_voted_id'] as String?,
      tie: json['tie'] == true,
      tally: tally,
      participants: _int(json['participants']),
    );
  }
}

class GameSession {
  final String id;
  final String activityId;
  final String gameType;
  final String hostUserId;
  final GameSessionStatus status;
  final int round;
  final Map<String, dynamic> state;
  final DateTime? updatedAt;
  final List<GamePlayer> players;

  const GameSession({
    required this.id,
    required this.activityId,
    required this.gameType,
    required this.hostUserId,
    required this.status,
    this.round = 1,
    this.state = const {},
    this.updatedAt,
    this.players = const [],
  });

  bool get isActive =>
      status == GameSessionStatus.lobby || status == GameSessionStatus.playing;

  ImpostorPhase get phase {
    if (status == GameSessionStatus.lobby) return ImpostorPhase.lobby;
    return switch (state['phase']) {
      'voting' => ImpostorPhase.voting,
      'result' => ImpostorPhase.result,
      'discussion' => ImpostorPhase.discussion,
      _ => status == GameSessionStatus.finished
          ? ImpostorPhase.result
          : ImpostorPhase.discussion,
    };
  }

  DateTime? get discussionEndsAt => _date(state['discussion_ends_at']);
  int get discussionSeconds => _int(state['discussion_seconds'], 180);
  String? get starterId => state['starter_id'] as String?;
  int get votesCount => _int(state['votes_count']);
  int get playerCount => _int(state['player_count'], players.length);

  ImpostorResult? get result {
    final raw = state['result'];
    return raw is Map<String, dynamic> ? ImpostorResult.fromJson(raw) : null;
  }

  bool isPlayer(String? userId) =>
      userId != null && players.any((p) => p.userId == userId);

  GamePlayer? playerById(String? userId) {
    for (final player in players) {
      if (player.userId == userId) return player;
    }
    return null;
  }

  factory GameSession.fromJson(Map<String, dynamic> json) {
    final players = [
      for (final row in (json['players'] as List? ?? const []))
        GamePlayer.fromJson(row as Map<String, dynamic>),
    ]..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return GameSession(
      id: json['id'] as String,
      activityId: json['activity_id'] as String,
      gameType: (json['game_type'] as String?) ?? 'impostor',
      hostUserId: json['host_user_id'] as String,
      status: _statusFrom(json['status'] as String?),
      round: _int(json['round'], 1),
      state: (json['state'] as Map?)?.cast<String, dynamic>() ?? const {},
      updatedAt: _date(json['updated_at']),
      players: players,
    );
  }
}

/// Lo que el usuario autenticado, y sólo él, sabe de la ronda.
class ImpostorRole {
  final bool isImpostor;

  /// La palabra secreta. Siempre null para el impostor: el servidor no se la
  /// escribe.
  final String? word;
  final int round;

  const ImpostorRole({required this.isImpostor, this.word, this.round = 1});

  factory ImpostorRole.fromJson(Map<String, dynamic> json) {
    final state = (json['state'] as Map?)?.cast<String, dynamic>() ?? const {};
    final isImpostor = state['role'] == 'impostor';
    return ImpostorRole(
      isImpostor: isImpostor,
      word: isImpostor ? null : state['word'] as String?,
      round: _int(json['round'], 1),
    );
  }
}

/// Miembro de la actividad, para armar equipos o brackets.
class ActivityMember {
  final String userId;
  final String name;
  final String imageUrl;
  final bool isOrganizer;

  const ActivityMember({
    required this.userId,
    required this.name,
    this.imageUrl = '',
    this.isOrganizer = false,
  });

  factory ActivityMember.fromJson(Map<String, dynamic> json) => ActivityMember(
        userId: json['user_id'] as String,
        name: (json['display_name'] as String?) ?? 'Participante',
        imageUrl: (json['profile_image_url'] as String?) ?? '',
        isOrganizer: json['is_organizer'] == true,
      );
}

/// Contenido de la tarjeta de resultado que se publica en el chat.
///
/// Viaja cifrado como cualquier otro mensaje; sólo lleva lo que se puede
/// contar al terminar la ronda, nunca los votos de cada persona.
class GameResultPayload {
  final String game;
  final String sessionId;
  final String winner;
  final String summary;
  final int participants;
  final String? word;

  const GameResultPayload({
    required this.game,
    required this.sessionId,
    required this.winner,
    required this.summary,
    required this.participants,
    this.word,
  });

  bool get groupWon => winner == 'group';

  Map<String, dynamic> toJson() => {
        'game': game,
        'session_id': sessionId,
        'winner': winner,
        'summary': summary,
        'participants': participants,
        if (word != null) 'word': word,
      };

  factory GameResultPayload.fromResult(String sessionId, ImpostorResult r) =>
      GameResultPayload(
        game: 'impostor',
        sessionId: sessionId,
        winner: r.winner,
        summary: r.summary,
        participants: r.participants,
        word: r.word,
      );

  /// null si el texto no es un resultado válido (mensaje ilegible, versión
  /// antigua o manipulado).
  static GameResultPayload? tryParse(Map<String, dynamic>? json) {
    if (json == null) return null;
    final game = json['game'];
    final session = json['session_id'];
    if (game is! String || session is! String) return null;
    return GameResultPayload(
      game: game,
      sessionId: session,
      winner: (json['winner'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      participants: _int(json['participants']),
      word: json['word'] as String?,
    );
  }
}
