import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:join_app/core/models/activity_model.dart';
import 'package:join_app/core/providers/app_state.dart';
import 'package:join_app/core/widgets/companion_view.dart';

import '../data/activity_game_models.dart';
import '../data/activity_game_repository.dart';
import '../domain/game_catalog.dart';
import 'games/classic_games.dart';
import 'games/group_games.dart';
import 'games/party_games.dart';
import 'widgets/game_ui.dart';

/// Centro de juegos de una actividad.
///
/// El contenido y los juegos sugeridos salen de [GameCatalog] según la
/// categoría del plan. El Impostor en línea se juega con salas compartidas;
/// el resto funciona en un solo teléfono y sin conexión.
class ActivityGamesScreen extends StatefulWidget {
  final String activityId;

  /// Para pruebas: evita consultar la sala activa en Supabase.
  final ActivityGameRepository? repository;

  const ActivityGamesScreen({
    super.key,
    required this.activityId,
    this.repository,
  });

  @override
  State<ActivityGamesScreen> createState() => _ActivityGamesScreenState();
}

class _ActivityGamesScreenState extends State<ActivityGamesScreen> {
  GameSession? _active;

  @override
  void initState() {
    super.initState();
    _loadActive();
  }

  Future<void> _loadActive() async {
    try {
      final repo = widget.repository ?? ActivityGameRepository();
      final active = await repo.fetchActiveSession(widget.activityId);
      if (mounted) setState(() => _active = active);
    } catch (_) {
      // Sin red, o sin la migración aplicada: los juegos locales siguen.
    }
  }

  Future<void> _openOnline() async {
    HapticFeedback.mediumImpact();
    await context.push('/main/activity/${widget.activityId}/games/impostor');
    _loadActive();
  }

  void _open(GameKind kind, GamePack pack) {
    HapticFeedback.selectionClick();
    if (kind == GameKind.impostorOnline) {
      _openOnline();
      return;
    }
    final repo = widget.repository;
    final Widget screen = switch (kind) {
      GameKind.impostorLocal => ImpostorLocalGameScreen(pack: pack),
      GameKind.dice => DiceGameScreen(pack: pack),
      GameKind.initial => InitialChallengeScreen(pack: pack),
      GameKind.teams => TeamsGameScreen(
          pack: pack, activityId: widget.activityId, repository: repo),
      GameKind.scoreboard => ScoreboardGameScreen(pack: pack),
      GameKind.bracket => BracketGameScreen(
          pack: pack, activityId: widget.activityId, repository: repo),
      GameKind.trivia => TriviaGameScreen(pack: pack),
      GameKind.bingo => BingoGameScreen(pack: pack),
      GameKind.wouldYouRather => WouldYouRatherScreen(pack: pack),
      GameKind.mostLikely => MostLikelyScreen(pack: pack),
      GameKind.debate => DebateGameScreen(pack: pack),
      GameKind.impostorOnline => const SizedBox.shrink(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final activity = appState.activities
        .where((a) => a.id == widget.activityId)
        .firstOrNull;
    final pack = GameCatalog.forCategory(activity?.category);
    final accent = pack.accent;
    final companion = appState.currentUser?.companionAsset ??
        'assets/images/mascota/ELI.png';

    final featured = pack.featured
        .where((k) => !GameCatalog.classics.contains(k))
        .toList();

    return GameScaffold(
      title: 'Centro de juegos',
      subtitle: activity?.title,
      accent: accent,
      body: RefreshIndicator(
        onRefresh: _loadActive,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _Hero(
              pack: pack,
              activity: activity,
              companion: companion,
            ).entrance(context),
            if (_active != null) ...[
              const SizedBox(height: 14),
              _ActiveSessionBanner(
                session: _active!,
                userId: appState.currentUser?.id,
                onTap: _openOnline,
              ).entrance(context, delayMs: 60),
            ],
            const SizedBox(height: 22),
            GameSectionTitle('Juega con todos desde su celular',
                accent: accent),
            _OnlineCard(
              info: GameCatalog.info[GameKind.impostorOnline]!,
              pack: pack,
              onTap: _openOnline,
            ).entrance(context, delayMs: 80),
            const SizedBox(height: 22),
            GameSectionTitle('Pensados para ${pack.label}', accent: accent),
            _FeaturedGrid(
              games: [for (final k in featured) GameCatalog.info[k]!],
              onTap: (k) => _open(k, pack),
            ),
            const SizedBox(height: 22),
            GameSectionTitle('Clásicos para cualquier plan', accent: accent),
            for (final (i, kind) in GameCatalog.classics.indexed)
              _GameListTile(
                info: GameCatalog.info[kind]!,
                onTap: () => _open(kind, pack),
              ).entrance(context, delayMs: 140 + 50 * i),
            const SizedBox(height: 12),
            _MoreGames(
              exclude: {...featured, ...GameCatalog.classics},
              onTap: (k) => _open(k, pack),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final GamePack pack;
  final Activity? activity;
  final String companion;

  const _Hero({
    required this.pack,
    required this.activity,
    required this.companion,
  });

  @override
  Widget build(BuildContext context) {
    final accent = pack.accent;
    final hsl = HSLColor.fromColor(accent);
    final deep = hsl
        .withLightness((hsl.lightness - 0.22).clamp(0.08, 1.0))
        .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .toColor();
    final participants = activity?.currentParticipants ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [deep, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(pack.icon, size: 13, color: Colors.white),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          pack.label.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Juguemos juntos',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4),
                ),
                const SizedBox(height: 5),
                Text(
                  participants > 0
                      ? '$participants participantes · juegos y retos elegidos para este plan'
                      : 'Juegos y retos elegidos para este plan',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 12,
                      height: 1.35),
                ),
              ],
            ),
          ),
          ExcludeSemantics(
            child: SizedBox(
              width: 96,
              height: 108,
              child: CompanionView(
                asset: companion,
                motion: CompanionMotion.celebrate,
                animationsEnabled: !reduceMotion(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveSessionBanner extends StatelessWidget {
  final GameSession session;
  final String? userId;
  final VoidCallback onTap;

  const _ActiveSessionBanner({
    required this.session,
    required this.userId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF8B5CF6);
    final p = GamePalette.of(context, accent);
    final playing = session.status == GameSessionStatus.playing;
    final mine = session.isPlayer(userId);
    final title = playing
        ? (mine ? 'Tu partida sigue en curso' : 'Hay una partida en curso')
        : 'Sala de El Impostor abierta';
    final action = mine
        ? 'Volver a la sala'
        : playing
            ? 'Ver la sala'
            : 'Unirme';

    return Semantics(
      button: true,
      label: '$title. ${session.players.length} jugadores. $action',
      excludeSemantics: true,
      child: Material(
        color: accent.withValues(alpha: p.isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                const _PulseDot(color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.w900, color: p.text)),
                      Text('${session.players.length} jugadores',
                          style: TextStyle(fontSize: 12, color: p.muted)),
                    ],
                  ),
                ),
                Text(action,
                    style: TextStyle(
                        fontWeight: FontWeight.w900, color: p.accentText)),
                Icon(Icons.chevron_right_rounded, color: p.accentText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  final Color color;

  const _PulseDot({required this.color});

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (reduceMotion(context)) return dot;
    return dot
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(
            begin: const Offset(0.8, 0.8),
            end: const Offset(1.2, 1.2),
            duration: 800.ms);
  }
}

class _OnlineCard extends StatelessWidget {
  final GameInfo info;
  final GamePack pack;
  final VoidCallback onTap;

  const _OnlineCard(
      {required this.info, required this.pack, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = info.color;
    return Semantics(
      button: true,
      label: '${info.title}. ${info.subtitle}. ${info.meta}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4C1D95), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(info.icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(info.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(
                        '${info.subtitle}. Palabras de ${pack.label}.',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 12.5,
                            height: 1.3),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _whiteChip(Icons.groups_rounded, '3–12'),
                          _whiteChip(Icons.timer_rounded, '${info.minutes} min'),
                          _whiteChip(Icons.lock_rounded, 'Rol privado'),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _whiteChip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _FeaturedGrid extends StatelessWidget {
  final List<GameInfo> games;
  final ValueChanged<GameKind> onTap;

  const _FeaturedGrid({required this.games, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Con texto grande, una columna: las tarjetas no se recortan.
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = constraints.maxWidth < 340 || scale > 1.3 ? 1 : 2;
      final width =
          (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (i, info) in games.indexed)
            SizedBox(
              width: width,
              child: _FeaturedCard(info: info, onTap: () => onTap(info.kind))
                  .entrance(context, delayMs: 100 + 60 * i),
            ),
        ],
      );
    });
  }
}

class _FeaturedCard extends StatelessWidget {
  final GameInfo info;
  final VoidCallback onTap;

  const _FeaturedCard({required this.info, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, info.color);
    return Semantics(
      button: true,
      label: '${info.title}. ${info.subtitle}. ${info.meta}',
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 150),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: info.color.withValues(alpha: 0.3)),
              gradient: LinearGradient(
                colors: [
                  info.color.withValues(alpha: p.isDark ? 0.16 : 0.10),
                  info.color.withValues(alpha: 0.0),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: info.color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(info.icon, color: p.accentText, size: 24),
                ),
                const SizedBox(height: 12),
                Text(info.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: p.text)),
                const SizedBox(height: 3),
                Text(info.subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 11.5, height: 1.3, color: p.muted)),
                const SizedBox(height: 8),
                Text(info.meta,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: p.accentText)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GameListTile extends StatelessWidget {
  final GameInfo info;
  final VoidCallback onTap;

  const _GameListTile({required this.info, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, info.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: '${info.title}. ${info.subtitle}. ${info.meta}',
        excludeSemantics: true,
        child: Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: p.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: info.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(info.icon, color: p.accentText, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(info.title,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                                color: p.text)),
                        const SizedBox(height: 2),
                        Text(info.subtitle,
                            style: TextStyle(fontSize: 12, color: p.muted)),
                        const SizedBox(height: 4),
                        Text(info.meta,
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: p.accentText)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: p.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El resto del catálogo, plegado para no saturar el menú.
class _MoreGames extends StatelessWidget {
  final Set<GameKind> exclude;
  final ValueChanged<GameKind> onTap;

  const _MoreGames({required this.exclude, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final rest = [
      for (final entry in GameCatalog.info.entries)
        if (!exclude.contains(entry.key) &&
            entry.key != GameKind.impostorOnline)
          entry.value,
    ];
    if (rest.isEmpty) return const SizedBox.shrink();
    final p = GamePalette.of(context, const Color(0xFF64748B));
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Más juegos (${rest.length})',
            style: TextStyle(fontWeight: FontWeight.w900, color: p.text)),
        children: [
          for (final info in rest)
            _GameListTile(info: info, onTap: () => onTap(info.kind)),
        ],
      ),
    );
  }
}
