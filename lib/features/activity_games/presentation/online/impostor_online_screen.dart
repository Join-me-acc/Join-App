import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:join_app/core/providers/app_state.dart';
import 'package:join_app/core/repositories/supabase_chat_repository.dart';

import '../../data/activity_game_models.dart';
import '../../data/activity_game_repository.dart';
import '../../domain/game_catalog.dart';
import '../activity_game_controller.dart';
import '../widgets/game_ui.dart';

const _impostorAccent = Color(0xFF8B5CF6);

/// El Impostor con cada jugador en su propio teléfono.
class ImpostorOnlineScreen extends StatefulWidget {
  final String activityId;

  /// Sala concreta (revancha desde el chat). Si es null se crea o se une a
  /// la sala activa del plan.
  final String? sessionId;

  /// Revancha de esta sala (desde la tarjeta del chat).
  final String? rematchOf;

  /// Para pruebas.
  final ImpostorRoomController? controller;

  const ImpostorOnlineScreen({
    super.key,
    required this.activityId,
    this.sessionId,
    this.rematchOf,
    this.controller,
  });

  @override
  State<ImpostorOnlineScreen> createState() => _ImpostorOnlineScreenState();
}

class _ImpostorOnlineScreenState extends State<ImpostorOnlineScreen> {
  late final ImpostorRoomController _controller;
  late final GamePack _pack;

  @override
  void initState() {
    super.initState();
    final activity = context
        .read<AppState>()
        .activities
        .where((a) => a.id == widget.activityId)
        .firstOrNull;
    _pack = GameCatalog.forCategory(activity?.category);

    final chat = SupabaseChatRepository();
    _controller = widget.controller ??
        ImpostorRoomController(
          repository: ActivityGameRepository(),
          activityId: widget.activityId,
          words: _pack.impostorWords,
          publishResult: (payload) => chat
              .sendGameResult(
                  activityId: widget.activityId, payload: payload.toJson())
              .then((_) {}),
        );
    if (widget.controller == null) {
      _controller.open(sessionId: widget.sessionId, rematchOf: widget.rematchOf);
    }
    _controller.addListener(_showErrors);
  }

  void _showErrors() {
    final error = _controller.error;
    if (error == null || !mounted || _controller.session == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(error),
      ));
    _controller.clearError();
  }

  @override
  void dispose() {
    _controller.removeListener(_showErrors);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<bool> _confirmLeave() async {
    final s = _controller.session;
    // En el lobby, salir libera el lugar. Durante la partida sólo se cierra
    // la pantalla: se puede volver desde el centro de juegos.
    if (s != null && s.status == GameSessionStatus.lobby && _controller.isPlayer) {
      await _controller.leave();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final s = _controller.session;
        return GameScaffold(
          title: 'El Impostor en línea',
          subtitle: s == null
              ? 'Palabras de ${_pack.label}'
              : '${s.players.length} jugadores · ronda ${s.round}',
          accent: _impostorAccent,
          onWillLeave: _confirmLeave,
          actions: [
            if (s != null && s.isActive && _controller.isHost)
              PopupMenuButton<String>(
                tooltip: 'Opciones de la sala',
                onSelected: (v) async {
                  if (v == 'cancel' && await _confirmCancel()) {
                    await _controller.cancel();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'cancel', child: Text('Cancelar partida')),
                ],
              ),
          ],
          body: Column(
            children: [
              if (_controller.offline) const _OfflineBanner(),
              Expanded(child: _body(s)),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _confirmCancel() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Cancelar la partida?'),
            content: const Text(
                'La sala se cerrará para todos los jugadores.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Seguir jugando')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Cancelar partida')),
            ],
          ),
        ) ??
        false;
  }

  Widget _body(GameSession? s) {
    final c = _controller;
    if (c.loading && s == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s == null) {
      return GameEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'No pudimos abrir la sala',
        message: c.error ?? 'Revisa tu conexión e inténtalo otra vez.',
        accent: _impostorAccent,
        actionLabel: 'Reintentar',
        onAction: () => c.open(sessionId: widget.sessionId, rematchOf: widget.rematchOf),
      );
    }
    if (s.status == GameSessionStatus.cancelled) {
      return GameEmptyState(
        icon: Icons.block_rounded,
        title: 'La partida se canceló',
        message: 'Pueden abrir una sala nueva cuando quieran.',
        accent: _impostorAccent,
        actionLabel: 'Abrir sala nueva',
        onAction: () => c.open(),
      );
    }

    final userId = c.userId;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        switch (s.phase) {
          ImpostorPhase.lobby => ImpostorLobbyView(
              session: s,
              userId: userId,
              isReady: c.isReady,
              busy: c.busy,
              onToggleReady: c.toggleReady,
              onStart: (seconds) => c.start(discussionSeconds: seconds),
              onJoin: () => c.open(),
            ),
          _ when !s.isPlayer(userId) && s.status == GameSessionStatus.playing =>
            _Spectator(session: s),
          ImpostorPhase.discussion => ImpostorDiscussionView(
              session: s,
              role: c.role,
              secondsLeft: c.secondsLeft ?? 0,
              canManage: c.isHost,
              busy: c.busy,
              onOpenVoting: c.openVoting,
            ),
          ImpostorPhase.voting => ImpostorVotingView(
              session: s,
              userId: userId,
              myVote: c.myVote,
              canManage: c.isHost,
              busy: c.busy,
              onVote: c.vote,
              onFinish: c.finish,
            ),
          ImpostorPhase.result => ImpostorResultView(
              session: s,
              userId: userId,
              isHost: c.isHost,
              busy: c.busy,
              onRematch: c.rematch,
              onBackToChat: () => context.go('/main/activity/${widget.activityId}/group'),
            ),
        },
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 18, color: Color(0xFFB45309)),
            SizedBox(width: 8),
            Expanded(
              child: Text('Sin conexión. Tu partida sigue guardada; reconectando…',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309))),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  LOBBY
// ════════════════════════════════════════════════════════════════════

class ImpostorLobbyView extends StatefulWidget {
  final GameSession session;
  final String? userId;
  final bool isReady;
  final bool busy;
  final VoidCallback onToggleReady;
  final ValueChanged<int> onStart;
  final VoidCallback onJoin;

  const ImpostorLobbyView({
    super.key,
    required this.session,
    required this.userId,
    required this.isReady,
    required this.busy,
    required this.onToggleReady,
    required this.onStart,
    required this.onJoin,
  });

  @override
  State<ImpostorLobbyView> createState() => _ImpostorLobbyViewState();
}

class _ImpostorLobbyViewState extends State<ImpostorLobbyView> {
  int _seconds = 180;

  @override
  Widget build(BuildContext context) {
    const accent = _impostorAccent;
    final p = GamePalette.of(context, accent);
    final s = widget.session;
    final isHost = s.hostUserId == widget.userId;
    final joined = s.isPlayer(widget.userId);
    final missing = 3 - s.players.length;
    final ready = s.players.where((pl) => pl.isReady).length;
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GameSurface(
          accent: accent,
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: p.accentGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_tethering_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(height: 12),
              Text('Sala de espera',
                  style: TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w900, color: p.text)),
              const SizedBox(height: 6),
              Text(
                missing > 0
                    ? 'Faltan $missing ${missing == 1 ? 'jugador' : 'jugadores'}. '
                        'Pídele a la gente del plan que abra Juegos.'
                    : '$ready de ${s.players.length} listos.'
                        '${isHost ? ' Empieza cuando quieras.' : ' Esperando al host.'}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.4, color: p.muted),
              ),
            ],
          ),
        ).entrance(context),
        const SizedBox(height: 18),
        GameSectionTitle('Jugadores', accent: accent,
            trailing: GameChip(text: '${s.players.length}/12', color: accent)),
        for (final (i, player) in s.players.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PlayerRow(
              player: player,
              isHost: player.userId == s.hostUserId,
              isMe: player.userId == widget.userId,
              online: player.isOnline(now),
            ).entrance(context, delayMs: 40 * i),
          ),
        const SizedBox(height: 14),
        if (!joined)
          GameButton(
            label: 'Unirme a la sala',
            icon: Icons.login_rounded,
            accent: accent,
            busy: widget.busy,
            onTap: widget.onJoin,
          )
        else ...[
          GameButton(
            label: widget.isReady ? '¡Listo! (toca para cancelar)' : 'Estoy listo',
            icon: widget.isReady
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            secondary: widget.isReady || isHost,
            accent: accent,
            onTap: widget.onToggleReady,
          ),
          if (isHost) ...[
            const SizedBox(height: 18),
            const GameSectionTitle('Tiempo de preguntas', accent: accent),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 120, label: Text('2 min')),
                ButtonSegment(value: 180, label: Text('3 min')),
                ButtonSegment(value: 300, label: Text('5 min')),
              ],
              selected: {_seconds},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _seconds = v.first),
            ),
            const SizedBox(height: 14),
            GameButton(
              label: missing > 0 ? 'Se necesitan 3 jugadores' : 'Empezar partida',
              icon: Icons.play_arrow_rounded,
              accent: accent,
              busy: widget.busy,
              onTap: missing > 0 ? null : () => widget.onStart(_seconds),
            ),
            const SizedBox(height: 8),
            Text(
              'El servidor elige la palabra y al impostor: ni tú sabrás quién es.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ],
        ],
      ],
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final GamePlayer player;
  final bool isHost;
  final bool isMe;
  final bool online;

  const _PlayerRow({
    required this.player,
    required this.isHost,
    required this.isMe,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    const accent = _impostorAccent;
    final p = GamePalette.of(context, accent);
    final status = [
      if (isHost) 'host',
      if (isMe) 'tú',
      player.isReady ? 'listo' : 'esperando',
      online ? 'conectado' : 'desconectado',
    ].join(', ');

    return Semantics(
      label: '${player.displayName}: $status',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: isMe ? accent.withValues(alpha: 0.5) : p.border),
        ),
        child: Row(
          children: [
            GameAvatar(
              name: player.displayName,
              imageUrl: player.imageUrl,
              accent: accent,
              online: online,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          isMe ? '${player.displayName} (tú)' : player.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: p.text),
                        ),
                      ),
                      if (isHost) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.workspace_premium_rounded,
                            size: 16, color: Color(0xFFF59E0B)),
                      ],
                    ],
                  ),
                  Text(
                    isHost
                        ? 'Host · ${online ? 'conectado' : 'sin señal'}'
                        : online
                            ? 'Conectado'
                            : 'Sin señal',
                    style: TextStyle(fontSize: 11.5, color: p.muted),
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: player.isReady
                  ? const Icon(Icons.check_circle_rounded,
                      key: ValueKey('ready'), color: Color(0xFF22C55E))
                  : Icon(Icons.hourglass_top_rounded,
                      key: const ValueKey('wait'), color: p.muted, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spectator extends StatelessWidget {
  final GameSession session;

  const _Spectator({required this.session});

  @override
  Widget build(BuildContext context) {
    return GameEmptyState(
      icon: Icons.visibility_rounded,
      title: 'Partida en curso',
      message:
          '${session.players.length} personas están jugando. Cuando terminen '
          'podrás entrar en la revancha.',
      accent: _impostorAccent,
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  ROL Y DISCUSIÓN
// ════════════════════════════════════════════════════════════════════

/// Tarjeta del rol propio. Se mantiene tapada hasta que el jugador la
/// presiona, para que nadie la vea por encima del hombro.
class ImpostorRoleCard extends StatefulWidget {
  final ImpostorRole? role;

  const ImpostorRoleCard({super.key, required this.role});

  @override
  State<ImpostorRoleCard> createState() => _ImpostorRoleCardState();
}

class _ImpostorRoleCardState extends State<ImpostorRoleCard> {
  bool _visible = false;

  void _show(bool visible) {
    if (visible) HapticFeedback.mediumImpact();
    setState(() => _visible = visible);
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.role;
    final isImpostor = role?.isImpostor ?? false;
    final colors = role == null || !_visible
        ? const [Color(0xFF6366F1), Color(0xFF4338CA)]
        : isImpostor
            ? const [Color(0xFFEF4444), Color(0xFF991B1B)]
            : const [Color(0xFF22C55E), Color(0xFF15803D)];

    final String title;
    final String subtitle;
    final IconData icon;
    if (role == null) {
      (title, subtitle, icon) =
          ('Repartiendo roles…', 'Un momento', Icons.hourglass_top_rounded);
    } else if (!_visible) {
      (title, subtitle, icon) = (
        'Mantén presionado para ver tu rol',
        'Suelta para volver a taparlo',
        Icons.fingerprint_rounded
      );
    } else if (isImpostor) {
      (title, subtitle, icon) = (
        '¡Eres el impostor!',
        'No conoces la palabra. Escucha, disimula y adivínala.',
        Icons.theater_comedy_rounded
      );
    } else {
      (title, subtitle, icon) = (
        role.word ?? '—',
        'Esta es la palabra secreta. Da pistas sin regalarla.',
        Icons.key_rounded
      );
    }

    return Semantics(
      button: role != null,
      label: role == null
          ? 'Repartiendo roles'
          : _visible
              ? '$title. $subtitle'
              : 'Mantén presionado para ver tu rol',
      excludeSemantics: true,
      // Los lectores de pantalla no pueden mantener presionado: un toque
      // alterna la tarjeta.
      onTap: role == null ? null : () => _show(!_visible),
      child: GestureDetector(
        onLongPressStart: role == null ? null : (_) => _show(true),
        onLongPressEnd: role == null ? null : (_) => _show(false),
        onTap: role == null ? null : () => _show(!_visible),
        child: AnimatedContainer(
          duration: Duration(milliseconds: reduceMotion(context) ? 0 : 240),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 210),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 44),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: _visible ? 28 : 18,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13.5,
                      height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}

class ImpostorDiscussionView extends StatelessWidget {
  final GameSession session;
  final ImpostorRole? role;
  final int secondsLeft;
  final bool canManage;
  final bool busy;
  final VoidCallback onOpenVoting;

  const ImpostorDiscussionView({
    super.key,
    required this.session,
    required this.role,
    required this.secondsLeft,
    required this.canManage,
    required this.busy,
    required this.onOpenVoting,
  });

  @override
  Widget build(BuildContext context) {
    const accent = _impostorAccent;
    final p = GamePalette.of(context, accent);
    final starter = session.playerById(session.starterId)?.displayName;
    final total = session.discussionSeconds;
    final minutes = secondsLeft ~/ 60;
    final seconds = (secondsLeft % 60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ImpostorRoleCard(role: role).entrance(context),
        const SizedBox(height: 18),
        GameSurface(
          accent: accent,
          child: Row(
            children: [
              SizedBox(
                width: 74,
                height: 74,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: total == 0 ? 0 : secondsLeft / total,
                      strokeWidth: 7,
                      strokeCap: StrokeCap.round,
                      color: secondsLeft <= 20
                          ? const Color(0xFFEF4444)
                          : accent,
                      backgroundColor: accent.withValues(alpha: 0.15),
                    ),
                    Center(
                      child: Semantics(
                        label: 'Quedan $minutes minutos y $seconds segundos',
                        excludeSemantics: true,
                        child: Text('$minutes:$seconds',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                                color: p.text,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ronda de preguntas',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: p.text)),
                    const SizedBox(height: 4),
                    Text(
                      starter == null
                          ? 'Cada uno da una pista por turno.'
                          : 'Empieza $starter. Luego sigan en ronda dando una pista cada uno.',
                      style: TextStyle(fontSize: 13, height: 1.35, color: p.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (canManage)
          GameButton(
            label: 'Pasar a la votación',
            icon: Icons.how_to_vote_rounded,
            accent: accent,
            busy: busy,
            onTap: onOpenVoting,
          )
        else
          Text(
            'La votación se abre al acabar el tiempo o cuando el host lo decida.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: p.muted),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  VOTACIÓN
// ════════════════════════════════════════════════════════════════════

class ImpostorVotingView extends StatelessWidget {
  final GameSession session;
  final String? userId;
  final String? myVote;
  final bool canManage;
  final bool busy;
  final ValueChanged<String> onVote;
  final VoidCallback onFinish;

  const ImpostorVotingView({
    super.key,
    required this.session,
    required this.userId,
    required this.myVote,
    required this.canManage,
    required this.busy,
    required this.onVote,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    const accent = _impostorAccent;
    final p = GamePalette.of(context, accent);
    final total = session.players.length;
    final votes = session.votesCount;
    final candidates =
        session.players.where((pl) => pl.userId != userId).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GameSurface(
          accent: accent,
          child: Column(
            children: [
              Icon(Icons.how_to_vote_rounded, size: 40, color: p.accentText),
              const SizedBox(height: 10),
              Text('¿Quién es el impostor?',
                  style: TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w900, color: p.text)),
              const SizedBox(height: 6),
              Text('Tu voto es secreto. Puedes cambiarlo hasta que voten todos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: p.muted)),
              const SizedBox(height: 14),
              Semantics(
                liveRegion: true,
                label: '$votes de $total votaron',
                excludeSemantics: true,
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: total == 0 ? 0 : votes / total,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                      color: accent,
                      backgroundColor: accent.withValues(alpha: 0.15),
                    ),
                    const SizedBox(height: 6),
                    Text('$votes de $total votaron',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: p.muted)),
                  ],
                ),
              ),
            ],
          ),
        ).entrance(context),
        const SizedBox(height: 16),
        for (final (i, player) in candidates.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _VoteTile(
              player: player,
              selected: myVote == player.userId,
              onTap: () => onVote(player.userId),
            ).entrance(context, delayMs: 40 * i),
          ),
        if (canManage) ...[
          const SizedBox(height: 8),
          GameButton(
            label: 'Cerrar votación y ver resultado',
            icon: Icons.flag_rounded,
            secondary: true,
            accent: accent,
            busy: busy,
            onTap: votes == 0 ? null : onFinish,
          ),
        ],
      ],
    );
  }
}

class _VoteTile extends StatelessWidget {
  final GamePlayer player;
  final bool selected;
  final VoidCallback onTap;

  const _VoteTile(
      {required this.player, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const accent = _impostorAccent;
    final p = GamePalette.of(context, accent);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Votar por ${player.displayName}',
      excludeSemantics: true,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.16) : p.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: selected ? accent : p.border, width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                GameAvatar(
                    name: player.displayName,
                    imageUrl: player.imageUrl,
                    accent: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(player.displayName,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: p.text)),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? accent : p.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  RESULTADO
// ════════════════════════════════════════════════════════════════════

class ImpostorResultView extends StatelessWidget {
  final GameSession session;
  final String? userId;
  final bool isHost;
  final bool busy;
  final VoidCallback onRematch;
  final VoidCallback onBackToChat;

  const ImpostorResultView({
    super.key,
    required this.session,
    required this.userId,
    required this.isHost,
    required this.busy,
    required this.onRematch,
    required this.onBackToChat,
  });

  @override
  Widget build(BuildContext context) {
    const accent = _impostorAccent;
    final p = GamePalette.of(context, accent);
    final result = session.result;
    if (result == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final wasImpostor = result.impostorId == userId;
    final played = session.isPlayer(userId);
    final iWon = wasImpostor ? !result.groupWon : result.groupWon;
    final colors = result.groupWon
        ? const [Color(0xFF22C55E), Color(0xFF15803D)]
        : const [Color(0xFFEF4444), Color(0xFF991B1B)];
    final maxVotes = result.tally.values.fold(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(
                  result.groupWon
                      ? Icons.groups_rounded
                      : Icons.theater_comedy_rounded,
                  color: Colors.white,
                  size: 50),
              const SizedBox(height: 10),
              Text(
                result.groupWon ? '¡Ganó el grupo!' : '¡Ganó el impostor!',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(result.summary,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                      height: 1.35)),
              if (played) ...[
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  iWon ? 'Tú también ganaste 🎉' : 'Esta vez no fue',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              ],
            ],
          ),
        ).pop(context, key: 'result-${session.id}'),
        const SizedBox(height: 16),
        GameSurface(
          accent: accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Fact(
                        label: 'Impostor',
                        value: result.impostorName ?? '—',
                        accent: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Fact(
                        label: 'Palabra', value: result.word ?? '—', accent: accent),
                  ),
                ],
              ),
              if (result.tally.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Votos recibidos',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, color: p.text)),
                const SizedBox(height: 10),
                for (final player in session.players)
                  if ((result.tally[player.userId] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(player.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: p.text)),
                          ),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: maxVotes == 0
                                  ? 0
                                  : result.tally[player.userId]! / maxVotes,
                              minHeight: 10,
                              borderRadius: BorderRadius.circular(10),
                              color: player.userId == result.impostorId
                                  ? const Color(0xFFEF4444)
                                  : accent,
                              backgroundColor: accent.withValues(alpha: 0.12),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('${result.tally[player.userId]}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, color: p.text)),
                        ],
                      ),
                    ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        GameButton(
          label: 'Revancha',
          icon: Icons.replay_rounded,
          accent: accent,
          busy: busy,
          onTap: onRematch,
        ),
        const SizedBox(height: 10),
        GameButton(
          label: 'Volver al chat',
          icon: Icons.chat_bubble_rounded,
          secondary: true,
          accent: accent,
          onTap: onBackToChat,
        ),
        if (isHost) ...[
          const SizedBox(height: 10),
          Text('El resultado se publicó en el chat del plan.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: p.muted)),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _Fact({required this.label, required this.value, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, accent);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: p.muted)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900, color: p.text)),
        ],
      ),
    );
  }
}
