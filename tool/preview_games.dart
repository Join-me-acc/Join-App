// flutter run -d chrome -t tool/preview_games.dart
// Arnés visual local del centro de juegos: no inicializa Supabase ni toca
// datos. Muestra cada juego con el contenido de la categoría elegida y las
// vistas de El Impostor en línea con una sala de ejemplo.
import 'package:flutter/material.dart';
import 'package:join_app/core/models/interest_model.dart';
import 'package:join_app/features/activity_games/data/activity_game_models.dart';
import 'package:join_app/features/activity_games/domain/game_catalog.dart';
import 'package:join_app/features/activity_games/presentation/games/classic_games.dart';
import 'package:join_app/features/activity_games/presentation/games/group_games.dart';
import 'package:join_app/features/activity_games/presentation/games/party_games.dart';
import 'package:join_app/features/activity_games/presentation/online/impostor_online_screen.dart';
import 'package:join_app/features/activity_games/presentation/widgets/game_result_card.dart';
import 'package:join_app/features/activity_games/presentation/widgets/game_ui.dart';

void main() => runApp(const GamesPreview());

class GamesPreview extends StatefulWidget {
  const GamesPreview({super.key});

  @override
  State<GamesPreview> createState() => _GamesPreviewState();
}

class _GamesPreviewState extends State<GamesPreview> {
  bool _dark = false;
  String _category = 'Deportes,Fútbol';

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFD7C36),
      brightness: _dark ? Brightness.dark : Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: _Menu(
        category: _category,
        dark: _dark,
        onCategory: (c) => setState(() => _category = c),
        onDark: (d) => setState(() => _dark = d),
      ),
    );
  }
}

GamePlayer _p(String id, String name, {bool ready = false}) => GamePlayer(
      userId: id,
      displayName: name,
      displayOrder: id.codeUnitAt(1),
      isReady: ready,
      lastSeenAt: DateTime.now(),
    );

final _players = [
  _p('u1', 'Ana Torres', ready: true),
  _p('u2', 'Beto Quispe', ready: true),
  _p('u3', 'Caro Ríos'),
  _p('u4', 'Diego Huamán', ready: true),
];

GameSession _session(GameSessionStatus status, Map<String, dynamic> state) =>
    GameSession(
      id: 's1',
      activityId: 'a1',
      gameType: 'impostor',
      hostUserId: 'u1',
      status: status,
      state: state,
      players: _players,
    );

class _Menu extends StatelessWidget {
  final String category;
  final bool dark;
  final ValueChanged<String> onCategory;
  final ValueChanged<bool> onDark;

  const _Menu({
    required this.category,
    required this.dark,
    required this.onCategory,
    required this.onDark,
  });

  @override
  Widget build(BuildContext context) {
    final pack = GameCatalog.forCategory(category);
    void open(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

    Widget online(String title, Widget view) => GameScaffold(
          title: title,
          accent: const Color(0xFF8B5CF6),
          body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [view]),
        );

    final items = <(String, Widget)>[
      ('Dados', DiceGameScreen(pack: pack)),
      ('Impostor (un celular)', ImpostorLocalGameScreen(pack: pack)),
      ('Reto por inicial', InitialChallengeScreen(pack: pack)),
      ('Marcador', ScoreboardGameScreen(pack: pack)),
      ('Trivia', TriviaGameScreen(pack: pack)),
      ('Bingo', BingoGameScreen(pack: pack)),
      ('¿Qué prefieres?', WouldYouRatherScreen(pack: pack)),
      ('¿Quién es más probable?', MostLikelyScreen(pack: pack)),
      ('Debate exprés', DebateGameScreen(pack: pack)),
      (
        'Online · lobby',
        online(
          'El Impostor en línea',
          ImpostorLobbyView(
            session: _session(GameSessionStatus.lobby, const {}),
            userId: 'u1',
            isReady: true,
            busy: false,
            onToggleReady: () {},
            onStart: (_) {},
            onJoin: () {},
          ),
        )
      ),
      (
        'Online · discusión',
        online(
          'El Impostor en línea',
          ImpostorDiscussionView(
            session: _session(GameSessionStatus.playing, {
              'phase': 'discussion',
              'discussion_seconds': 180,
              'starter_id': 'u3',
            }),
            role: ImpostorRole(
                isImpostor: false, word: pack.impostorWords.first),
            secondsLeft: 124,
            canManage: true,
            busy: false,
            onOpenVoting: () {},
          ),
        )
      ),
      (
        'Online · votación',
        online(
          'El Impostor en línea',
          ImpostorVotingView(
            session: _session(GameSessionStatus.playing,
                {'phase': 'voting', 'votes_count': 2}),
            userId: 'u1',
            myVote: 'u3',
            canManage: true,
            busy: false,
            onVote: (_) {},
            onFinish: () {},
          ),
        )
      ),
      (
        'Online · resultado',
        online(
          'El Impostor en línea',
          ImpostorResultView(
            session: _session(GameSessionStatus.finished, {
              'phase': 'result',
              'result': {
                'winner': 'group',
                'summary': 'El grupo descubrió a Caro Ríos',
                'impostor_id': 'u3',
                'impostor_name': 'Caro Ríos',
                'word': pack.impostorWords.first,
                'tally': [
                  {'user_id': 'u3', 'votes': 3},
                  {'user_id': 'u2', 'votes': 1},
                ],
                'participants': 4,
              },
            }),
            userId: 'u1',
            isHost: true,
            busy: false,
            onRematch: () {},
            onBackToChat: () {},
          ),
        )
      ),
      (
        'Tarjeta en el chat',
        Scaffold(
          appBar: AppBar(title: const Text('Chat')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            GameResultCard(
              payload: GameResultPayload(
                game: 'impostor',
                sessionId: 's1',
                winner: 'impostor',
                summary:
                    'El grupo acusó a Beto Quispe y Caro Ríos se salió con la suya',
                participants: 4,
                word: pack.impostorWords.first,
              ),
              authorName: 'Ana Torres',
              timeLabel: 'Hace 2m',
              onRematch: () {},
            ),
          ]),
        )
      ),
    ];

    return GameScaffold(
      title: 'Vista previa de juegos',
      subtitle: '${pack.label} · ${pack.featured.map((k) => GameCatalog.info[k]!.title).join(', ')}',
      accent: pack.accent,
      actions: [
        IconButton(
          tooltip: 'Tema',
          icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
          onPressed: () => onDark(!dark),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in [
                ...CategoryConstants.mainCategories,
                'Deportes,Fútbol',
                'Playa',
                'Programación',
              ])
                ChoiceChip(
                  label: Text(c),
                  selected: c == category,
                  onSelected: (_) => onCategory(c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (title, screen) in items)
            ListTile(
              title: Text(title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(screen),
            ),
          ListTile(
            title: const Text('Equipos (sin red: añade invitados)'),
            onTap: () => open(TeamsGameScreen(pack: pack, activityId: 'a1')),
          ),
          ListTile(
            title: const Text('Bracket (sin red: añade invitados)'),
            onTap: () => open(BracketGameScreen(pack: pack, activityId: 'a1')),
          ),
        ],
      ),
    );
  }
}
