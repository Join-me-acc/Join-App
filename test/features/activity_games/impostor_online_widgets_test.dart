import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:join_app/features/activity_games/data/activity_game_models.dart';
import 'package:join_app/features/activity_games/data/activity_game_repository.dart';
import 'package:join_app/features/activity_games/presentation/activity_game_controller.dart';
import 'package:join_app/features/activity_games/presentation/online/impostor_online_screen.dart';
import 'package:join_app/features/activity_games/presentation/widgets/game_result_card.dart';

GamePlayer player(String id, String name, {bool ready = false}) => GamePlayer(
      userId: id,
      displayName: name,
      displayOrder: id.hashCode,
      isReady: ready,
      lastSeenAt: DateTime.now(),
    );

GameSession session({
  GameSessionStatus status = GameSessionStatus.lobby,
  List<GamePlayer>? players,
  Map<String, dynamic> state = const {},
  String host = 'u1',
}) =>
    GameSession(
      id: 's1',
      activityId: 'a1',
      gameType: 'impostor',
      hostUserId: host,
      status: status,
      state: state,
      players: players ?? [player('u1', 'Ana'), player('u2', 'Beto')],
    );

Widget wrap(Widget child, {bool disableAnimations = true}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  group('Lobby', () {
    testWidgets('el host no puede empezar con menos de 3 jugadores',
        (tester) async {
      var started = false;
      await tester.pumpWidget(wrap(ImpostorLobbyView(
        session: session(),
        userId: 'u1',
        isReady: false,
        busy: false,
        onToggleReady: () {},
        onStart: (_) => started = true,
        onJoin: () {},
      )));

      expect(find.text('Se necesitan 3 jugadores'), findsOneWidget);
      expect(find.textContaining('Faltan 1 jugador'), findsOneWidget);
      await tester.tap(find.text('Se necesitan 3 jugadores'));
      expect(started, isFalse);
    });

    testWidgets('con 3 jugadores el host inicia con el tiempo elegido',
        (tester) async {
      int? seconds;
      await tester.pumpWidget(wrap(ImpostorLobbyView(
        session: session(players: [
          player('u1', 'Ana'),
          player('u2', 'Beto', ready: true),
          player('u3', 'Caro'),
        ]),
        userId: 'u1',
        isReady: false,
        busy: false,
        onToggleReady: () {},
        onStart: (s) => seconds = s,
        onJoin: () {},
      )));

      await tester.tap(find.text('5 min'));
      await tester.pump();
      await tester.ensureVisible(find.text('Empezar partida'));
      await tester.tap(find.text('Empezar partida'));
      expect(seconds, 300);
      // Indicador visible del host.
      expect(find.byIcon(Icons.workspace_premium_rounded), findsOneWidget);
    });

    testWidgets('un participante no ve el botón de iniciar', (tester) async {
      await tester.pumpWidget(wrap(ImpostorLobbyView(
        session: session(),
        userId: 'u2',
        isReady: true,
        busy: false,
        onToggleReady: () {},
        onStart: (_) {},
        onJoin: () {},
      )));
      expect(find.text('Empezar partida'), findsNothing);
      expect(find.text('Se necesitan 3 jugadores'), findsNothing);
      expect(find.textContaining('¡Listo!'), findsOneWidget);
    });

    testWidgets('quien no está en la sala puede unirse', (tester) async {
      var joined = false;
      await tester.pumpWidget(wrap(ImpostorLobbyView(
        session: session(),
        userId: 'u9',
        isReady: false,
        busy: false,
        onToggleReady: () {},
        onStart: (_) {},
        onJoin: () => joined = true,
      )));
      await tester.tap(find.text('Unirme a la sala'));
      expect(joined, isTrue);
    });
  });

  group('Rol privado', () {
    testWidgets('la palabra queda tapada hasta tocar la tarjeta',
        (tester) async {
      await tester.pumpWidget(wrap(const ImpostorRoleCard(
          role: ImpostorRole(isImpostor: false, word: 'Ceviche'))));
      expect(find.text('Ceviche'), findsNothing);
      await tester.tap(find.byType(ImpostorRoleCard));
      await tester.pump();
      expect(find.text('Ceviche'), findsOneWidget);
      await tester.tap(find.byType(ImpostorRoleCard));
      await tester.pump();
      expect(find.text('Ceviche'), findsNothing);
    });

    testWidgets('el impostor ve su rol y ninguna palabra', (tester) async {
      await tester.pumpWidget(
          wrap(const ImpostorRoleCard(role: ImpostorRole(isImpostor: true))));
      await tester.tap(find.byType(ImpostorRoleCard));
      await tester.pump();
      expect(find.text('¡Eres el impostor!'), findsOneWidget);
    });
  });

  testWidgets('en la votación no aparece uno mismo', (tester) async {
    String? voted;
    await tester.pumpWidget(wrap(ImpostorVotingView(
      session: session(
        status: GameSessionStatus.playing,
        state: {'phase': 'voting', 'votes_count': 1},
        players: [player('u1', 'Ana'), player('u2', 'Beto'), player('u3', 'Caro')],
      ),
      userId: 'u1',
      myVote: null,
      canManage: false,
      busy: false,
      onVote: (id) => voted = id,
      onFinish: () {},
    )));

    expect(find.text('Ana'), findsNothing);
    expect(find.text('1 de 3 votaron'), findsOneWidget);
    await tester.tap(find.text('Caro'));
    expect(voted, 'u3');
  });

  testWidgets('tarjeta de resultado en el chat', (tester) async {
    var rematch = false;
    await tester.pumpWidget(wrap(GameResultCard(
      payload: const GameResultPayload(
        game: 'impostor',
        sessionId: 's1',
        winner: 'group',
        summary: 'El grupo descubrió a Beto',
        participants: 4,
        word: 'Cancha',
      ),
      authorName: 'Ana',
      timeLabel: 'Ahora',
      onRematch: () => rematch = true,
    )));
    expect(find.text('¡Ganó el grupo!'), findsOneWidget);
    expect(find.text('4 jugadores'), findsOneWidget);
    await tester.tap(find.text('Revancha'));
    expect(rematch, isTrue);
  });

  group('ImpostorRoomController', () {
    testWidgets('entra a la sala, conserva el estado sin red y se recupera',
        (tester) async {
      final repo = _FakeRepository();
      final c = ImpostorRoomController(
          repository: repo, activityId: 'a1', words: const ['Pelota']);
      await c.open();
      expect(repo.createCalls, 1);
      expect(c.session?.id, 's1');
      expect(c.isHost, isTrue);
      expect(repo.subscribed, isTrue);

      repo.failNext = true;
      await c.refresh();
      expect(c.offline, isTrue);
      expect(c.session, isNotNull, reason: 'no se pierde la partida');

      await c.refresh();
      expect(c.offline, isFalse);

      c.dispose();
      expect(repo.subscribed, isFalse);
    });

    testWidgets('el host publica el resultado una sola vez', (tester) async {
      ImpostorRoomController.publishedSessions.clear();
      final repo = _FakeRepository()
        ..next = session(status: GameSessionStatus.finished, state: {
          'phase': 'result',
          'result': {
            'winner': 'impostor',
            'summary': 'Beto se salió con la suya',
            'participants': 3,
          },
        });
      final published = <GameResultPayload>[];
      final c = ImpostorRoomController(
        repository: repo,
        activityId: 'a1',
        words: const ['Pelota'],
        publishResult: (p) async => published.add(p),
      );
      await c.open(sessionId: 's1');
      await c.refresh();
      await c.refresh();
      expect(published, hasLength(1));
      expect(published.single.summary, 'Beto se salió con la suya');
      c.dispose();
    });

    testWidgets('un jugador que no es host no publica', (tester) async {
      ImpostorRoomController.publishedSessions.clear();
      final repo = _FakeRepository()
        ..me = 'u2'
        ..next = session(status: GameSessionStatus.finished, state: {
          'phase': 'result',
          'result': {'winner': 'group', 'summary': 'x', 'participants': 3},
        });
      final published = <GameResultPayload>[];
      final c = ImpostorRoomController(
        repository: repo,
        activityId: 'a1',
        words: const ['Pelota'],
        publishResult: (p) async => published.add(p),
      );
      await c.open(sessionId: 's1');
      expect(published, isEmpty);
      c.dispose();
    });

    testWidgets('el voto se refleja al instante y se revierte si falla',
        (tester) async {
      final repo = _FakeRepository()
        ..next = session(
          status: GameSessionStatus.playing,
          state: {'phase': 'voting'},
          players: [player('u1', 'Ana'), player('u2', 'Beto'), player('u3', 'Caro')],
        );
      final c = ImpostorRoomController(
          repository: repo, activityId: 'a1', words: const ['Pelota']);
      await c.open(sessionId: 's1');

      repo.failVote = true;
      await c.vote('u2');
      expect(c.myVote, isNull);
      expect(c.error, isNotNull);

      repo.failVote = false;
      await c.vote('u3');
      expect(c.myVote, 'u3');
      expect(repo.votes, ['u3']);
      c.dispose();
    });
  });
}

class _FakeRepository implements ActivityGameRepository {
  String me = 'u1';
  GameSession? next;
  bool failNext = false;
  bool failVote = false;
  bool subscribed = false;
  int createCalls = 0;
  final votes = <String>[];

  @override
  String? get currentUserId => me;

  @override
  Future<String> createOrJoin(String activityId,
      {String gameType = 'impostor'}) async {
    createCalls++;
    return 's1';
  }

  @override
  Future<GameSession?> fetchSession(String sessionId) async {
    if (failNext) {
      failNext = false;
      throw Exception('SocketException: sin red');
    }
    return next ?? session();
  }

  @override
  Future<ImpostorRole?> fetchMyRole(String sessionId) async =>
      const ImpostorRole(isImpostor: false, word: 'Pelota');

  @override
  Future<String?> fetchMyVote(String sessionId, int round) async => null;

  @override
  Future<void> vote(String sessionId, String targetId) async {
    if (failVote) throw Exception('La votación no está abierta.');
    votes.add(targetId);
  }

  @override
  Future<void> Function() subscribe(String sessionId, void Function() onChange) {
    subscribed = true;
    return () async => subscribed = false;
  }

  @override
  Future<void> heartbeat(String sessionId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
