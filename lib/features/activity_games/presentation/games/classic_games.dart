import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/game_catalog.dart';
import '../widgets/game_ui.dart';

// ════════════════════════════════════════════════════════════════════
//  DADOS
// ════════════════════════════════════════════════════════════════════

class DiceGameScreen extends StatefulWidget {
  final GamePack pack;
  final Random? random;

  const DiceGameScreen({super.key, required this.pack, this.random});

  @override
  State<DiceGameScreen> createState() => _DiceGameScreenState();
}

class _DiceGameScreenState extends State<DiceGameScreen> {
  late final Random _random = widget.random ?? Random();
  int _count = 2;
  List<int> _values = [1, 6];
  int _rolls = 0;
  final List<int> _history = [];

  void _roll() {
    HapticFeedback.heavyImpact();
    setState(() {
      _values = List.generate(_count, (_) => _random.nextInt(6) + 1);
      _rolls++;
      _history.insert(0, _values.fold(0, (a, b) => a + b));
      if (_history.length > 8) _history.removeLast();
    });
  }

  void _setCount(int count) {
    setState(() {
      _count = count;
      _values = List.generate(count, (i) => i == 0 ? 1 : 6 - (i % 6));
      _history.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = GameCatalog.info[GameKind.dice]!;
    final accent = info.color;
    final p = GamePalette.of(context, accent);
    final total = _values.fold(0, (a, b) => a + b);

    return GameScaffold(
      title: info.title,
      subtitle: 'Para ${widget.pack.label}',
      accent: accent,
      bottom: GameButton(
        label: _rolls == 0 ? 'Lanzar dados' : 'Lanzar otra vez',
        icon: Icons.casino_rounded,
        accent: accent,
        onTap: _roll,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          GameSurface(
            accent: accent,
            child: Column(
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1 dado')),
                    ButtonSegment(value: 2, label: Text('2 dados')),
                    ButtonSegment(value: 3, label: Text('3 dados')),
                  ],
                  selected: {_count},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _setCount(s.first),
                ),
                const SizedBox(height: 26),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final (i, v) in _values.indexed)
                      DieFace(value: v, accent: accent, size: 86)
                          .pop(context, key: '$i-$v-$_rolls'),
                  ],
                ),
                const SizedBox(height: 22),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _rolls == 0 ? '¿Quién lanza primero?' : 'Total: $total',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: p.text),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Úsenlos para decidir turnos, quién paga el pasaje o quién elige la música.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.4),
                ),
              ],
            ),
          ).entrance(context),
          if (_history.length > 1) ...[
            const SizedBox(height: 18),
            GameSectionTitle('Últimos lanzamientos', accent: accent),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, h) in _history.skip(1).indexed)
                  GameChip(
                      text: '$h',
                      color: accent,
                      icon: i == 0 ? Icons.history_rounded : null),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Cara de dado con puntos dibujados: los glifos ⚀–⚅ dependen de la fuente
/// del sistema y en varios Android se veían como cuadros vacíos.
class DieFace extends StatelessWidget {
  final int value;
  final Color accent;
  final double size;

  const DieFace({
    super.key,
    required this.value,
    required this.accent,
    this.size = 80,
  }) : assert(value >= 1 && value <= 6);

  static const _layouts = <int, List<(double, double)>>{
    1: [(0.5, 0.5)],
    2: [(0.27, 0.27), (0.73, 0.73)],
    3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
    4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
    5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
    6: [
      (0.27, 0.25), (0.73, 0.25), (0.27, 0.5),
      (0.73, 0.5), (0.27, 0.75), (0.73, 0.75),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, accent);
    final dot = size * 0.17;
    return Semantics(
      label: 'Dado: $value',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: p.isDark ? const Color(0xFF232A38) : Colors.white,
          borderRadius: BorderRadius.circular(size * 0.24),
          border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.6),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Stack(
          children: [
            for (final (x, y) in _layouts[value]!)
              Positioned(
                left: x * size - dot / 2,
                top: y * size - dot / 2,
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: value == 1 ? accent : p.text,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  EL IMPOSTOR (un solo celular)
// ════════════════════════════════════════════════════════════════════

class ImpostorLocalGameScreen extends StatefulWidget {
  final GamePack pack;
  final Random? random;

  const ImpostorLocalGameScreen({super.key, required this.pack, this.random});

  @override
  State<ImpostorLocalGameScreen> createState() =>
      _ImpostorLocalGameScreenState();
}

enum _LocalStage { setup, reveal, debate, unmask }

class _ImpostorLocalGameScreenState extends State<ImpostorLocalGameScreen> {
  late final Random _random = widget.random ?? Random();
  _LocalStage _stage = _LocalStage.setup;
  int _players = 4;
  int _impostor = 0;
  int _current = 0;
  int _starter = 0;
  bool _revealed = false;
  String _word = '';
  final List<String> _usedWords = [];

  void _deal() {
    HapticFeedback.mediumImpact();
    final words = widget.pack.impostorWords
        .where((w) => !_usedWords.contains(w))
        .toList();
    if (words.isEmpty) _usedWords.clear();
    final pool = words.isEmpty ? widget.pack.impostorWords : words;
    setState(() {
      _word = pool[_random.nextInt(pool.length)];
      _usedWords.add(_word);
      _impostor = _random.nextInt(_players);
      _starter = _random.nextInt(_players);
      _current = 0;
      _revealed = false;
      _stage = _LocalStage.reveal;
    });
  }

  void _tapCard() {
    HapticFeedback.mediumImpact();
    setState(() {
      if (!_revealed) {
        _revealed = true;
      } else {
        _revealed = false;
        _current++;
        if (_current >= _players) _stage = _LocalStage.debate;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = GameCatalog.info[GameKind.impostorLocal]!;
    final accent = info.color;
    return GameScaffold(
      title: 'El Impostor',
      subtitle: 'Palabras de ${widget.pack.label}',
      accent: accent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          switch (_stage) {
            _LocalStage.setup => _setup(accent),
            _LocalStage.reveal => _reveal(accent),
            _LocalStage.debate => _debate(accent),
            _LocalStage.unmask => _unmask(accent),
          },
        ],
      ),
    );
  }

  Widget _setup(Color accent) {
    final p = GamePalette.of(context, accent);
    return GameSurface(
      accent: accent,
      child: Column(
        children: [
          Icon(Icons.visibility_off_rounded, size: 44, color: p.accentText),
          const SizedBox(height: 12),
          Text(
            'Todos verán la misma palabra, menos el impostor. Pasen el celular, '
            'hagan preguntas y descubran quién miente.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: p.muted),
          ),
          const SizedBox(height: 22),
          GameCounter(
            value: _players,
            min: 3,
            max: 12,
            label: 'jugadores',
            accent: accent,
            onChanged: (v) => setState(() => _players = v),
          ),
          const SizedBox(height: 24),
          GameButton(
            label: 'Repartir roles',
            icon: Icons.play_arrow_rounded,
            accent: accent,
            onTap: _deal,
          ),
        ],
      ),
    ).entrance(context);
  }

  Widget _reveal(Color accent) {
    final p = GamePalette.of(context, accent);
    final isImpostor = _current == _impostor;
    final colors = !_revealed
        ? [const Color(0xFF6366F1), const Color(0xFF4338CA)]
        : isImpostor
            ? [const Color(0xFFEF4444), const Color(0xFF991B1B)]
            : [const Color(0xFF22C55E), const Color(0xFF15803D)];

    return Column(
      children: [
        Text('Jugador ${_current + 1} de $_players',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: p.muted)),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: (_current + (_revealed ? 1 : 0)) / _players,
          minHeight: 6,
          borderRadius: BorderRadius.circular(6),
          color: accent,
          backgroundColor: accent.withValues(alpha: 0.15),
        ),
        const SizedBox(height: 20),
        Semantics(
          button: true,
          label: _revealed
              ? (isImpostor
                  ? 'Eres el impostor. Toca para pasar al siguiente.'
                  : 'La palabra es $_word. Toca para pasar al siguiente.')
              : 'Toca para revelar tu rol',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: _tapCard,
            child: AnimatedContainer(
              duration: Duration(milliseconds: reduceMotion(context) ? 0 : 280),
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 260),
              padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 22),
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
                children: _revealed
                    ? [
                        Icon(
                            isImpostor
                                ? Icons.theater_comedy_rounded
                                : Icons.handshake_rounded,
                            color: Colors.white,
                            size: 48),
                        const SizedBox(height: 14),
                        Text(
                          isImpostor ? '¡Eres el impostor!' : _word,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isImpostor
                              ? 'Disimula y trata de adivinar la palabra'
                              : 'Esa es la palabra secreta. Shhh…',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13.5),
                        ),
                        const SizedBox(height: 18),
                        _pill('Ocultar y pasar el celular'),
                      ]
                    : [
                        const Icon(Icons.lock_rounded,
                            color: Colors.white, size: 46),
                        const SizedBox(height: 14),
                        const Text('Toca para ver tu rol',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text('Que nadie más mire',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 13.5)),
                      ],
              ),
            ),
          ),
        ).pop(context, key: '$_current-$_revealed'),
      ],
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700)),
      );

  Widget _debate(Color accent) {
    final p = GamePalette.of(context, accent);
    return GameSurface(
      accent: accent,
      child: Column(
        children: [
          Icon(Icons.forum_rounded, size: 46, color: p.accentText),
          const SizedBox(height: 12),
          Text('¡Que empiece el debate!',
              style: TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w900, color: p.text)),
          const SizedBox(height: 8),
          Text(
            'Empieza preguntando el jugador ${_starter + 1}. Cada uno dice una '
            'pista sobre la palabra sin regalarla. Al final, voten señalando al '
            'sospechoso.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: p.muted),
          ),
          const SizedBox(height: 22),
          GameButton(
            label: 'Revelar al impostor',
            icon: Icons.visibility_rounded,
            accent: accent,
            onTap: () => setState(() => _stage = _LocalStage.unmask),
          ),
        ],
      ),
    ).entrance(context);
  }

  Widget _unmask(Color accent) {
    final p = GamePalette.of(context, accent);
    return GameSurface(
      accent: accent,
      child: Column(
        children: [
          Text('El impostor era',
              style: TextStyle(fontSize: 14, color: p.muted)),
          const SizedBox(height: 6),
          Text('Jugador ${_impostor + 1}',
              style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w900, color: p.text)),
          const SizedBox(height: 14),
          GameChip(text: 'La palabra: $_word', color: accent, icon: Icons.key_rounded),
          const SizedBox(height: 24),
          GameButton(
            label: 'Otra ronda',
            icon: Icons.refresh_rounded,
            accent: accent,
            onTap: _deal,
          ),
          const SizedBox(height: 10),
          GameButton(
            label: 'Cambiar jugadores',
            secondary: true,
            accent: accent,
            onTap: () => setState(() => _stage = _LocalStage.setup),
          ),
        ],
      ),
    ).pop(context, key: 'unmask');
  }
}

// ════════════════════════════════════════════════════════════════════
//  RETO POR INICIAL
// ════════════════════════════════════════════════════════════════════

class InitialChallengeScreen extends StatefulWidget {
  final GamePack pack;
  final Random? random;

  const InitialChallengeScreen({super.key, required this.pack, this.random});

  @override
  State<InitialChallengeScreen> createState() => _InitialChallengeScreenState();
}

class _InitialChallengeScreenState extends State<InitialChallengeScreen> {
  // Letras con las que empiezan nombres comunes en el Perú; se omiten las
  // que casi nunca tocarían a nadie (K, Ñ, Q, W, X, Y, Z).
  static const _letters = 'ABCDEFGHIJLMNOPRSTV';

  late final Random _random = widget.random ?? Random();
  String? _letter;
  String _challenge = '';
  int _count = 0;
  final List<String> _recent = [];

  void _next() {
    HapticFeedback.mediumImpact();
    final challenges = widget.pack.initialChallenges
        .where((c) => !_recent.contains(c))
        .toList();
    final pool = challenges.isEmpty ? widget.pack.initialChallenges : challenges;
    String letter;
    do {
      letter = _letters[_random.nextInt(_letters.length)];
    } while (letter == _letter);
    setState(() {
      _letter = letter;
      _challenge = pool[_random.nextInt(pool.length)];
      _recent.add(_challenge);
      if (_recent.length > 4) _recent.removeAt(0);
      _count++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = GameCatalog.info[GameKind.initial]!;
    final accent = info.color;
    final p = GamePalette.of(context, accent);
    return GameScaffold(
      title: info.title,
      subtitle: 'Retos de ${widget.pack.label}',
      accent: accent,
      bottom: GameButton(
        label: _letter == null ? 'Sortear letra' : 'Otra letra',
        icon: Icons.shuffle_rounded,
        accent: accent,
        onTap: _next,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          GameSurface(
            accent: accent,
            padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
            child: Column(
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    gradient: GamePalette.of(context, accent).accentGradient,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.4),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _letter ?? '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 60,
                        fontWeight: FontWeight.w900),
                  ),
                ).pop(context, key: '$_letter-$_count'),
                const SizedBox(height: 22),
                Semantics(
                  liveRegion: true,
                  child: _letter == null
                      ? Text(
                          'Sorteen una letra: quien tenga un nombre que empiece '
                          'por ella cumple el reto.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 15, height: 1.45, color: p.muted),
                        )
                      : Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text: 'Quien tenga un nombre con "$_letter"\n',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: p.muted,
                                    fontWeight: FontWeight.w600)),
                            TextSpan(
                                text: _challenge,
                                style: TextStyle(
                                    fontSize: 19,
                                    height: 1.4,
                                    color: p.text,
                                    fontWeight: FontWeight.w900)),
                          ]),
                          textAlign: TextAlign.center,
                        ),
                ),
                if (_count > 0) ...[
                  const SizedBox(height: 16),
                  GameChip(
                      text: '$_count ${_count == 1 ? 'reto' : 'retos'} cumplidos',
                      color: accent,
                      icon: Icons.local_fire_department_rounded),
                ],
              ],
            ),
          ).entrance(context),
          const SizedBox(height: 14),
          Text(
            '¿Nadie tiene esa letra? Lo cumple quien sorteó.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: p.muted),
          ),
        ],
      ),
    );
  }
}
