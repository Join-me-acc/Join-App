import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/game_catalog.dart';
import '../../domain/game_logic.dart';
import '../widgets/game_ui.dart';

// ════════════════════════════════════════════════════════════════════
//  TRIVIA
// ════════════════════════════════════════════════════════════════════

class TriviaGameScreen extends StatefulWidget {
  final GamePack pack;
  final Random? random;

  const TriviaGameScreen({super.key, required this.pack, this.random});

  @override
  State<TriviaGameScreen> createState() => _TriviaGameScreenState();
}

class _TriviaGameScreenState extends State<TriviaGameScreen> {
  static const _roundSize = 8;
  late final Random _random = widget.random ?? Random();
  late List<TriviaQuestion> _questions;
  int _index = 0;
  int? _picked;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  void _newRound() {
    _questions = pickTrivia(widget.pack.trivia, _roundSize, _random);
    _index = 0;
    _picked = null;
    _score = 0;
  }

  void _pick(int option) {
    if (_picked != null) return;
    final correct = option == _questions[_index].answer;
    correct ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
    setState(() {
      _picked = option;
      if (correct) _score++;
    });
  }

  void _next() => setState(() {
        _index++;
        _picked = null;
      });

  @override
  Widget build(BuildContext context) {
    final info = GameCatalog.info[GameKind.trivia]!;
    final accent = widget.pack.accent;
    final finished = _index >= _questions.length;

    return GameScaffold(
      title: info.title,
      subtitle: 'Preguntas de ${widget.pack.label}',
      accent: accent,
      bottom: finished
          ? GameButton(
              label: 'Jugar otra ronda',
              icon: Icons.refresh_rounded,
              accent: accent,
              onTap: () => setState(_newRound),
            )
          : GameButton(
              label: _index == _questions.length - 1
                  ? 'Ver resultado'
                  : 'Siguiente pregunta',
              icon: Icons.arrow_forward_rounded,
              accent: accent,
              onTap: _picked == null ? null : _next,
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          finished ? _summary(accent) : _question(accent),
        ],
      ),
    );
  }

  Widget _question(Color accent) {
    final p = GamePalette.of(context, accent);
    final q = _questions[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GameChip(
                text: 'Pregunta ${_index + 1} de ${_questions.length}',
                color: accent),
            const Spacer(),
            GameChip(
                text: '$_score aciertos',
                color: const Color(0xFF22C55E),
                icon: Icons.check_circle_rounded),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: (_index + (_picked == null ? 0 : 1)) / _questions.length,
          minHeight: 6,
          borderRadius: BorderRadius.circular(6),
          color: accent,
          backgroundColor: accent.withValues(alpha: 0.15),
        ),
        const SizedBox(height: 18),
        GameSurface(
          accent: accent,
          child: Text(
            q.question,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 19,
                height: 1.35,
                fontWeight: FontWeight.w900,
                color: p.text),
          ),
        ).pop(context, key: 'q$_index'),
        const SizedBox(height: 14),
        for (final (i, option) in q.options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OptionTile(
              letter: String.fromCharCode(65 + i),
              text: option,
              accent: accent,
              state: _picked == null
                  ? _OptionState.idle
                  : i == q.answer
                      ? _OptionState.correct
                      : i == _picked
                          ? _OptionState.wrong
                          : _OptionState.dimmed,
              onTap: () => _pick(i),
            ).entrance(context, delayMs: 50 * i),
          ),
        if (_picked != null && q.fact != null)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_rounded, size: 18, color: p.accentText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(q.fact!,
                      style: TextStyle(
                          fontSize: 13, height: 1.4, color: p.text)),
                ),
              ],
            ),
          ).entrance(context),
      ],
    );
  }

  Widget _summary(Color accent) {
    final p = GamePalette.of(context, accent);
    final ratio = _score / _questions.length;
    final (title, icon) = ratio >= 0.85
        ? ('¡Nivel experto!', Icons.workspace_premium_rounded)
        : ratio >= 0.5
            ? ('¡Bien jugado!', Icons.thumb_up_alt_rounded)
            : ('Hay revancha', Icons.sentiment_satisfied_alt_rounded);
    return GameSurface(
      accent: accent,
      child: Column(
        children: [
          Icon(icon, size: 56, color: p.accentText),
          const SizedBox(height: 10),
          Text(title,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w900, color: p.text)),
          const SizedBox(height: 6),
          Text('$_score de ${_questions.length} respuestas correctas',
              style: TextStyle(fontSize: 14.5, color: p.muted)),
        ],
      ),
    ).pop(context, key: 'summary');
  }
}

enum _OptionState { idle, correct, wrong, dimmed }

class _OptionTile extends StatelessWidget {
  final String letter;
  final String text;
  final Color accent;
  final _OptionState state;
  final VoidCallback onTap;

  const _OptionTile({
    required this.letter,
    required this.text,
    required this.accent,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, accent);
    const green = Color(0xFF22C55E);
    const red = Color(0xFFEF4444);
    final color = switch (state) {
      _OptionState.correct => green,
      _OptionState.wrong => red,
      _ => accent,
    };
    final filled =
        state == _OptionState.correct || state == _OptionState.wrong;

    return Semantics(
      button: state == _OptionState.idle,
      label: '$letter. $text'
          '${state == _OptionState.correct ? ', respuesta correcta' : ''}'
          '${state == _OptionState.wrong ? ', incorrecta' : ''}',
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: state == _OptionState.dimmed ? 0.5 : 1,
        child: Material(
          color: filled ? color.withValues(alpha: 0.16) : p.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: state == _OptionState.idle ? onTap : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: filled ? color : p.border, width: filled ? 1.8 : 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: filled
                        ? Icon(
                            state == _OptionState.correct
                                ? Icons.check_rounded
                                : Icons.close_rounded,
                            size: 18,
                            color: color)
                        : Text(letter,
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: p.accentText)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(text,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: p.text)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  BINGO DE EXPLORACIÓN
// ════════════════════════════════════════════════════════════════════

class BingoGameScreen extends StatefulWidget {
  final GamePack pack;
  final Random? random;

  const BingoGameScreen({super.key, required this.pack, this.random});

  @override
  State<BingoGameScreen> createState() => _BingoGameScreenState();
}

class _BingoGameScreenState extends State<BingoGameScreen> {
  late final Random _random = widget.random ?? Random();
  late List<String> _card = pickBingoCard(widget.pack.bingo, _random);
  final _marked = <int>{};

  void _toggle(int i) {
    final before = completedBingoLines(_marked);
    setState(() => _marked.contains(i) ? _marked.remove(i) : _marked.add(i));
    final after = completedBingoLines(_marked);
    if (after > before) {
      HapticFeedback.heavyImpact();
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(_marked.length == 9
            ? '¡Cartón lleno! Bingo total 🎉'
            : '¡Línea! Llevan $after'),
      ));
    } else {
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = GameCatalog.info[GameKind.bingo]!;
    final accent = widget.pack.accent;
    final p = GamePalette.of(context, accent);
    final lines = completedBingoLines(_marked);

    return GameScaffold(
      title: info.title,
      subtitle: widget.pack.label,
      accent: accent,
      actions: [
        IconButton(
          tooltip: 'Nuevo cartón',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => setState(() {
            _card = pickBingoCard(widget.pack.bingo, _random);
            _marked.clear();
          }),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Marquen cada cosa cuando la encuentren durante el plan. Una línea '
            'vale, el cartón lleno es leyenda.',
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              GameChip(text: '${_marked.length}/9 encontrados', color: accent),
              const SizedBox(width: 8),
              if (lines > 0)
                GameChip(
                    text: '$lines ${lines == 1 ? 'línea' : 'líneas'}',
                    color: const Color(0xFF22C55E),
                    icon: Icons.emoji_events_rounded),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _card.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            itemBuilder: (context, i) {
              final on = _marked.contains(i);
              return Semantics(
                button: true,
                toggled: on,
                label: _card[i],
                excludeSemantics: true,
                child: Material(
                  color: on ? accent : p.surface,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _toggle(i),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: on ? accent : p.border, width: 1.2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                              on
                                  ? Icons.check_circle_rounded
                                  : Icons.search_rounded,
                              size: 20,
                              color: on ? Colors.white : p.accentText),
                          const SizedBox(height: 6),
                          Flexible(
                            child: Text(
                              _card[i],
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.fade,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                color: on ? Colors.white : p.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ).entrance(context, delayMs: 30 * i);
            },
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  ¿QUÉ PREFIERES?
// ════════════════════════════════════════════════════════════════════

class WouldYouRatherScreen extends StatefulWidget {
  final GamePack pack;
  final Random? random;

  const WouldYouRatherScreen({super.key, required this.pack, this.random});

  @override
  State<WouldYouRatherScreen> createState() => _WouldYouRatherScreenState();
}

class _WouldYouRatherScreenState extends State<WouldYouRatherScreen> {
  late final Random _random = widget.random ?? Random();
  final List<(String, String)> _recent = [];
  late (String, String) _current = _draw();
  int _votesA = 0;
  int _votesB = 0;
  int _round = 1;

  (String, String) _draw() {
    final pick = drawFresh(widget.pack.wouldYouRather, _recent, _random).first;
    _recent.add(pick);
    if (_recent.length > 5) _recent.removeAt(0);
    return pick;
  }

  void _next() {
    HapticFeedback.mediumImpact();
    setState(() {
      _current = _draw();
      _votesA = 0;
      _votesB = 0;
      _round++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = GameCatalog.info[GameKind.wouldYouRather]!;
    final accent = info.color;
    final p = GamePalette.of(context, accent);
    final total = _votesA + _votesB;

    Widget option(String text, int votes, Color color, VoidCallback onTap) {
      final share = total == 0 ? 0.0 : votes / total;
      return Expanded(
        child: Semantics(
          button: true,
          label: '$text. $votes votos. Toca para votar.',
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.75)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedFractionallySizedBox(
                          duration: const Duration(milliseconds: 300),
                          heightFactor: share,
                          widthFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    height: 1.25,
                                    fontWeight: FontWeight.w900)),
                            if (total > 0) ...[
                              const SizedBox(height: 10),
                              Text('${(share * 100).round()}% · $votes',
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontWeight: FontWeight.w800)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GameScaffold(
      title: info.title,
      subtitle: 'Ronda $_round · ${widget.pack.label}',
      accent: accent,
      bottom: GameButton(
        label: 'Otra pregunta',
        icon: Icons.skip_next_rounded,
        accent: accent,
        onTap: _next,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          children: [
            Text('Toquen su opción para votar y defiendan su elección.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 14),
            Expanded(
              child: Column(
                key: ValueKey(_round),
                children: [
                  option(_current.$1, _votesA, const Color(0xFF6366F1),
                      () => setState(() => _votesA++)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: p.border),
                      ),
                      child: Text('o',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: p.text)),
                    ),
                  ),
                  option(_current.$2, _votesB, const Color(0xFFEC4899),
                      () => setState(() => _votesB++)),
                ],
              ).entrance(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  ¿QUIÉN ES MÁS PROBABLE QUE…?
// ════════════════════════════════════════════════════════════════════

class MostLikelyScreen extends StatefulWidget {
  final GamePack pack;
  final Random? random;

  const MostLikelyScreen({super.key, required this.pack, this.random});

  @override
  State<MostLikelyScreen> createState() => _MostLikelyScreenState();
}

class _MostLikelyScreenState extends State<MostLikelyScreen> {
  late final Random _random = widget.random ?? Random();
  final List<String> _recent = [];
  late String _prompt = _draw();
  int _count = 1;
  int? _countdown;
  Timer? _timer;

  String _draw() {
    final pick = drawFresh(widget.pack.mostLikely, _recent, _random).first;
    _recent.add(pick);
    if (_recent.length > 4) _recent.removeAt(0);
    return pick;
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 3);
    HapticFeedback.selectionClick();
    _timer = Timer.periodic(const Duration(milliseconds: 800), (t) {
      if (!mounted) return t.cancel();
      setState(() => _countdown = _countdown! - 1);
      if (_countdown! <= 0) {
        HapticFeedback.heavyImpact();
        t.cancel();
      } else {
        HapticFeedback.selectionClick();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = GameCatalog.info[GameKind.mostLikely]!;
    final accent = info.color;
    final p = GamePalette.of(context, accent);

    return GameScaffold(
      title: info.title,
      subtitle: widget.pack.label,
      accent: accent,
      bottom: Row(
        children: [
          Expanded(
            child: GameButton(
              label: '3, 2, 1…',
              icon: Icons.timer_rounded,
              secondary: true,
              accent: accent,
              onTap: _startCountdown,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GameButton(
              label: 'Siguiente',
              icon: Icons.skip_next_rounded,
              accent: accent,
              onTap: () {
                _timer?.cancel();
                HapticFeedback.mediumImpact();
                setState(() {
                  _prompt = _draw();
                  _countdown = null;
                  _count++;
                });
              },
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 280),
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              gradient: GamePalette.of(context, accent).accentGradient,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Carta $_count',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                const Text('¿Quién es más probable que…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text('$_prompt?',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          height: 1.25,
                          fontWeight: FontWeight.w900)),
                ),
                if (_countdown != null) ...[
                  const SizedBox(height: 22),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _countdown! > 0 ? '$_countdown' : '¡Señalen!',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w900),
                    ).pop(context, key: 'c$_countdown'),
                  ),
                ],
              ],
            ),
          ).pop(context, key: 'card$_count'),
          const SizedBox(height: 16),
          Text(
            'Lean la carta, cuenten hasta tres y todos señalan a la vez. '
            'El más señalado cuenta por qué.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  DEBATE EXPRÉS
// ════════════════════════════════════════════════════════════════════

class DebateGameScreen extends StatefulWidget {
  final GamePack pack;
  final Random? random;

  const DebateGameScreen({super.key, required this.pack, this.random});

  @override
  State<DebateGameScreen> createState() => _DebateGameScreenState();
}

class _DebateGameScreenState extends State<DebateGameScreen> {
  static const _turnSeconds = 60;
  late final Random _random = widget.random ?? Random();
  final List<String> _recent = [];
  late String _topic = _draw();

  /// 0: a favor, 1: en contra, 2: terminado.
  int _turn = 0;
  int _left = _turnSeconds;
  Timer? _timer;

  String _draw() {
    final pick = drawFresh(widget.pack.debateTopics, _recent, _random).first;
    _recent.add(pick);
    if (_recent.length > 4) _recent.removeAt(0);
    return pick;
  }

  bool get _running => _timer?.isActive ?? false;

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() {});
      return;
    }
    if (_turn >= 2) return;
    HapticFeedback.selectionClick();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        HapticFeedback.heavyImpact();
        setState(() {
          _turn++;
          _left = _turnSeconds;
        });
      }
    });
    setState(() {});
  }

  void _newTopic() {
    _timer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _topic = _draw();
      _turn = 0;
      _left = _turnSeconds;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = GameCatalog.info[GameKind.debate]!;
    final accent = info.color;
    final p = GamePalette.of(context, accent);
    final side = switch (_turn) {
      0 => ('A favor', const Color(0xFF22C55E)),
      1 => ('En contra', const Color(0xFFEF4444)),
      _ => ('¡A votar!', accent),
    };

    return GameScaffold(
      title: info.title,
      subtitle: widget.pack.label,
      accent: accent,
      bottom: Row(
        children: [
          Expanded(
            child: GameButton(
              label: 'Otro tema',
              icon: Icons.shuffle_rounded,
              secondary: true,
              accent: accent,
              onTap: _newTopic,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GameButton(
              label: _turn >= 2
                  ? 'Terminado'
                  : _running
                      ? 'Pausar'
                      : 'Iniciar turno',
              icon: _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
              accent: accent,
              onTap: _turn >= 2 ? null : _toggle,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          GameSurface(
            accent: accent,
            child: Column(
              children: [
                GameChip(text: 'Tema', color: accent, icon: Icons.forum_rounded),
                const SizedBox(height: 12),
                Text(_topic,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 21,
                        height: 1.3,
                        fontWeight: FontWeight.w900,
                        color: p.text)),
              ],
            ),
          ).pop(context, key: _topic),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 170,
              height: 170,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: _turn >= 2 ? 1 : _left / _turnSeconds,
                    strokeWidth: 10,
                    strokeCap: StrokeCap.round,
                    color: side.$2,
                    backgroundColor: side.$2.withValues(alpha: 0.15),
                  ),
                  Center(
                    child: Semantics(
                      liveRegion: _left % 15 == 0,
                      label: '${side.$1}, quedan $_left segundos',
                      excludeSemantics: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(side.$1,
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: GamePalette.of(context, side.$2)
                                      .accentText)),
                          if (_turn < 2)
                            Text('$_left',
                                style: TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.w900,
                                    color: p.text,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ])),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _turn >= 2
                ? 'Ambos bandos hablaron. Voten a mano alzada qué argumento convenció más.'
                : 'Un minuto por bando. Se vale sumar datos, ejemplos y mucha pasión.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}
