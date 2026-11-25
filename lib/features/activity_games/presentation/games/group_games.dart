import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/activity_game_repository.dart';
import '../../domain/game_catalog.dart';
import '../../domain/game_logic.dart';
import '../widgets/game_ui.dart';

// ════════════════════════════════════════════════════════════════════
//  Lista de jugadores (miembros del plan + invitados)
// ════════════════════════════════════════════════════════════════════

/// Carga a la gente del plan y deja añadir invitados que no tienen la app.
class _Roster extends StatefulWidget {
  final String activityId;
  final Color accent;
  final ValueChanged<List<String>> onChanged;
  final ActivityGameRepository? repository;

  const _Roster({
    required this.activityId,
    required this.accent,
    required this.onChanged,
    this.repository,
  });

  @override
  State<_Roster> createState() => _RosterState();
}

class _RosterState extends State<_Roster> {
  final _names = <String>[];
  final _selected = <String>{};
  final _controller = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = widget.repository ?? ActivityGameRepository();
      final members = await repo.fetchMembers(widget.activityId);
      _names.addAll(members.map((m) => m.name));
    } catch (_) {
      // Sin red se puede jugar igual escribiendo los nombres.
    }
    if (!mounted) return;
    setState(() {
      _selected.addAll(_names);
      _loading = false;
    });
    _emit();
  }

  void _emit() => widget.onChanged([
        for (final n in _names)
          if (_selected.contains(n)) n
      ]);

  void _add() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    var unique = name;
    var i = 2;
    while (_names.contains(unique)) {
      unique = '$name $i';
      i++;
    }
    setState(() {
      _names.add(unique);
      _selected.add(unique);
      _controller.clear();
    });
    _emit();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, widget.accent);
    return GameSurface(
      accent: widget.accent,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_alt_rounded, size: 18, color: p.accentText),
              const SizedBox(width: 8),
              Expanded(
                child: Text('¿Quiénes juegan? (${_selected.length})',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: p.text)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in _names)
                  FilterChip(
                    label: Text(name),
                    selected: _selected.contains(name),
                    onSelected: (on) {
                      setState(() => on ? _selected.add(name) : _selected.remove(name));
                      _emit();
                    },
                    selectedColor: widget.accent.withValues(alpha: 0.2),
                    checkmarkColor: p.accentText,
                  ),
              ],
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(
              hintText: 'Añadir invitado',
              isDense: true,
              filled: true,
              fillColor: p.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                tooltip: 'Añadir',
                icon: Icon(Icons.person_add_alt_1_rounded, color: p.accentText),
                onPressed: _add,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _teamColors = [
  Color(0xFFEF4444),
  Color(0xFF3B82F6),
  Color(0xFF22C55E),
  Color(0xFFF59E0B),
];

const _teamNames = ['Equipo Rojo', 'Equipo Azul', 'Equipo Verde', 'Equipo Amarillo'];

// ════════════════════════════════════════════════════════════════════
//  ARMAR EQUIPOS
// ════════════════════════════════════════════════════════════════════

class TeamsGameScreen extends StatefulWidget {
  final GamePack pack;
  final String activityId;
  final Random? random;
  final ActivityGameRepository? repository;

  const TeamsGameScreen({
    super.key,
    required this.pack,
    required this.activityId,
    this.random,
    this.repository,
  });

  @override
  State<TeamsGameScreen> createState() => _TeamsGameScreenState();
}

class _TeamsGameScreenState extends State<TeamsGameScreen> {
  late final Random _random = widget.random ?? Random();
  List<String> _players = [];
  int _teamCount = 2;
  List<List<String>>? _teams;

  void _shuffle() {
    HapticFeedback.mediumImpact();
    setState(() {
      _teams = splitIntoTeams(_players, _teamCount, _random);
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = GameCatalog.info[GameKind.teams]!;
    final accent = info.color;
    final p = GamePalette.of(context, accent);
    final canShuffle = _players.length >= _teamCount;

    return GameScaffold(
      title: info.title,
      subtitle: widget.pack.label,
      accent: accent,
      bottom: GameButton(
        label: _teams == null ? 'Armar equipos' : 'Volver a sortear',
        icon: Icons.shuffle_rounded,
        accent: accent,
        onTap: canShuffle ? _shuffle : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _Roster(
            activityId: widget.activityId,
            accent: accent,
            repository: widget.repository,
            onChanged: (names) => setState(() {
              _players = names;
              _teams = null;
            }),
          ).entrance(context),
          const SizedBox(height: 16),
          GameSurface(
            accent: accent,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Text('Número de equipos',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: p.text)),
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 2, label: Text('2')),
                    ButtonSegment(value: 3, label: Text('3')),
                    ButtonSegment(value: 4, label: Text('4')),
                  ],
                  selected: {_teamCount},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _teamCount = s.first;
                    _teams = null;
                  }),
                ),
              ],
            ),
          ),
          if (!canShuffle) ...[
            const SizedBox(height: 12),
            Text('Selecciona al menos $_teamCount personas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 12.5)),
          ],
          if (_teams != null) ...[
            const SizedBox(height: 20),
            for (final (i, team) in _teams!.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TeamCard(
                  name: _teamNames[i],
                  color: _teamColors[i],
                  members: team,
                ).entrance(context, delayMs: 70 * i),
              ),
          ],
        ],
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final String name;
  final Color color;
  final List<String> members;

  const _TeamCard(
      {required this.name, required this.color, required this.members});

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, color);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_rounded, color: color, size: 20),
              const SizedBox(width: 8),
              Text(name,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: p.accentText)),
              const Spacer(),
              Text('${members.length}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: p.muted)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in members)
                Chip(
                  avatar: GameAvatar(name: m, accent: color, size: 24),
                  label: Text(m),
                  backgroundColor: p.surface,
                  side: BorderSide(color: color.withValues(alpha: 0.25)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  MARCADOR RÁPIDO
// ════════════════════════════════════════════════════════════════════

class ScoreboardGameScreen extends StatefulWidget {
  final GamePack pack;

  const ScoreboardGameScreen({super.key, required this.pack});

  @override
  State<ScoreboardGameScreen> createState() => _ScoreboardGameScreenState();
}

class _ScoreboardGameScreenState extends State<ScoreboardGameScreen> {
  final _names = ['Local', 'Visita'];
  final _scores = [0, 0];
  final List<int> _undo = [];

  void _add(int team, int delta) {
    if (_scores[team] + delta < 0) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _scores[team] += delta;
      if (delta > 0) _undo.add(team);
    });
  }

  Future<void> _rename(int team) async {
    final controller = TextEditingController(text: _names[team]);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre del equipo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Guardar')),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      setState(() => _names[team] = name.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = GameCatalog.info[GameKind.scoreboard]!;
    final accent = info.color;
    final p = GamePalette.of(context, accent);
    final leader = _scores[0] == _scores[1] ? -1 : (_scores[0] > _scores[1] ? 0 : 1);

    return GameScaffold(
      title: info.title,
      subtitle: widget.pack.label,
      accent: accent,
      actions: [
        IconButton(
          tooltip: 'Deshacer último punto',
          icon: const Icon(Icons.undo_rounded),
          onPressed: _undo.isEmpty
              ? null
              : () => setState(() => _scores[_undo.removeLast()]--),
        ),
        IconButton(
          tooltip: 'Reiniciar marcador',
          icon: const Icon(Icons.restart_alt_rounded),
          onPressed: () => setState(() {
            _scores[0] = 0;
            _scores[1] = 0;
            _undo.clear();
          }),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (final team in [0, 1]) ...[
                    if (team == 1) const SizedBox(width: 12),
                    Expanded(
                      child: _ScoreColumn(
                        name: _names[team],
                        score: _scores[team],
                        color: _teamColors[team == 0 ? 0 : 1],
                        leading: leader == team,
                        onPlus: () => _add(team, 1),
                        onMinus: () => _add(team, -1),
                        onRename: () => _rename(team),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Toca el número para sumar. Mantén presionado el nombre para cambiarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  final String name;
  final int score;
  final Color color;
  final bool leading;
  final VoidCallback onPlus;
  final VoidCallback onMinus;
  final VoidCallback onRename;

  const _ScoreColumn({
    required this.name,
    required this.score,
    required this.color,
    required this.leading,
    required this.onPlus,
    required this.onMinus,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, color);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: p.isDark ? 0.32 : 0.18),
            color.withValues(alpha: p.isDark ? 0.12 : 0.05),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
            color: color.withValues(alpha: leading ? 0.9 : 0.3),
            width: leading ? 2.2 : 1),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          GestureDetector(
            onLongPress: onRename,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.emoji_events_rounded,
                          size: 18, color: color),
                    ),
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: p.accentText)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Cambiar nombre',
                    icon: Icon(Icons.edit_rounded, size: 16, color: p.muted),
                    onPressed: onRename,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: '$name: $score puntos. Toca para sumar un punto.',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: onPlus,
                child: Center(
                  child: FittedBox(
                    child: Text('$score',
                        style: TextStyle(
                            fontSize: 96,
                            fontWeight: FontWeight.w900,
                            color: p.text,
                            fontFeatures: const [FontFeature.tabularFigures()]))
                        .pop(context, key: '$name-$score'),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GameRoundButton(
                  icon: Icons.remove_rounded,
                  accent: color,
                  semanticLabel: 'Restar un punto a $name',
                  onTap: score > 0 ? onMinus : null,
                ),
                const SizedBox(width: 14),
                GameRoundButton(
                  icon: Icons.add_rounded,
                  accent: color,
                  semanticLabel: 'Sumar un punto a $name',
                  onTap: onPlus,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  BRACKET RÁPIDO
// ════════════════════════════════════════════════════════════════════

class BracketGameScreen extends StatefulWidget {
  final GamePack pack;
  final String activityId;
  final Random? random;
  final ActivityGameRepository? repository;

  const BracketGameScreen({
    super.key,
    required this.pack,
    required this.activityId,
    this.random,
    this.repository,
  });

  @override
  State<BracketGameScreen> createState() => _BracketGameScreenState();
}

class _BracketGameScreenState extends State<BracketGameScreen> {
  late final Random _random = widget.random ?? Random();
  List<String> _players = [];
  Bracket? _bracket;

  @override
  Widget build(BuildContext context) {
    final info = GameCatalog.info[GameKind.bracket]!;
    final accent = info.color;
    final p = GamePalette.of(context, accent);
    final bracket = _bracket;

    return GameScaffold(
      title: info.title,
      subtitle: widget.pack.label,
      accent: accent,
      bottom: bracket == null
          ? GameButton(
              label: 'Sortear llaves',
              icon: Icons.account_tree_rounded,
              accent: accent,
              onTap: _players.length >= 3 && _players.length <= 16
                  ? () {
                      HapticFeedback.mediumImpact();
                      setState(() =>
                          _bracket = Bracket.seeded(_players, random: _random));
                    }
                  : null,
            )
          : GameButton(
              label: 'Nuevo torneo',
              icon: Icons.refresh_rounded,
              secondary: true,
              accent: accent,
              onTap: () => setState(() => _bracket = null),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (bracket == null) ...[
            _Roster(
              activityId: widget.activityId,
              accent: accent,
              repository: widget.repository,
              onChanged: (names) => setState(() => _players = names),
            ).entrance(context),
            const SizedBox(height: 12),
            Text(
              'Entre 3 y 16 jugadores. Si no cuadra en potencia de dos, a algunos '
              'les toca pase directo a la siguiente ronda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
            ),
          ] else ...[
            if (bracket.champion != null)
              GameSurface(
                accent: accent,
                child: Column(
                  children: [
                    const Icon(Icons.emoji_events_rounded,
                        size: 54, color: Color(0xFFF59E0B)),
                    const SizedBox(height: 8),
                    Text('¡${bracket.champion} es campeón!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: p.text)),
                  ],
                ),
              ).pop(context, key: bracket.champion),
            for (final (r, round) in bracket.rounds.indexed) ...[
              const SizedBox(height: 16),
              GameSectionTitle(bracket.roundName(r), accent: accent),
              for (final (m, match) in round.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MatchCard(
                    match: match,
                    accent: accent,
                    onPick: (winner) {
                      HapticFeedback.selectionClick();
                      setState(() => bracket.setWinner(r, m, winner));
                    },
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final BracketMatch match;
  final Color accent;
  final ValueChanged<String> onPick;

  const _MatchCard(
      {required this.match, required this.accent, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, accent);

    Widget side(String? name) {
      final isWinner = name != null && match.winner == name;
      final playable = name != null && match.isPlayable;
      return Expanded(
        child: Semantics(
          button: playable,
          selected: isWinner,
          label: name == null ? 'Por definir' : 'Ganador: $name',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: playable ? () => onPick(name) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
              decoration: BoxDecoration(
                color: isWinner
                    ? accent.withValues(alpha: 0.2)
                    : p.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isWinner ? accent : Colors.transparent, width: 1.6),
              ),
              child: Text(
                name ?? (match.isBye ? 'Pase directo' : 'Por definir'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isWinner ? FontWeight.w900 : FontWeight.w700,
                  color: name == null ? p.muted : p.text,
                  fontStyle: name == null ? FontStyle.italic : null,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        side(match.a),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('vs',
              style: TextStyle(fontWeight: FontWeight.w900, color: p.muted)),
        ),
        side(match.b),
      ],
    );
  }
}
