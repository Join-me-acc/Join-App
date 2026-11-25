import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:join_app/core/models/activity_model.dart';
import 'package:join_app/core/providers/app_state.dart';
import 'package:join_app/core/theme/app_colors.dart';
import 'package:join_app/core/widgets/companion_view.dart';

enum _GameView { menu, dice, impostor, initial }

/// Centro de juegos de una actividad. Mantiene cada partida en el dispositivo
/// por ahora, pero recibe el ID del plan para personalizar su contenido.
class ActivityGamesScreen extends StatefulWidget {
  final String activityId;

  const ActivityGamesScreen({super.key, required this.activityId});

  @override
  State<ActivityGamesScreen> createState() => _ActivityGamesScreenState();
}

class _ActivityGamesScreenState extends State<ActivityGamesScreen> {
  _GameView _view = _GameView.menu;
  final _random = Random();

  // ── Dados ──────────────────────────────────────────────────
  int _die1 = 1;
  int _die2 = 6;
  int _rollCount = 0;

  // ── Impostor ───────────────────────────────────────────────
  int _players = 4;
  int _impostorIndex = 0;
  int _currentPlayer = 0;
  bool _revealed = false;
  bool _impostorStarted = false;
  String _secretWord = '';
  // ── Reto por inicial ───────────────────────────────────────
  String _letter = '?';
  String _challenge = 'Presiona el botón para empezar';
  int _challengeCount = 0;
  Activity? get _activity => context
      .read<AppState>()
      .activities
      .where((activity) => activity.id == widget.activityId)
      .firstOrNull;

  List<String> _secretWordsFor(Activity? activity) {
    final category = activity?.category.toLowerCase() ?? '';
    if (category.contains('deport')) {
      return ['Cancha', 'Árbitro', 'Camiseta', 'Pelota', 'Capitán', 'Tribuna'];
    }
    if (category.contains('comida') || category.contains('gastronom')) {
      return ['Ceviche', 'Anticuchos', 'Chifa', 'Postre', 'Ají', 'Cafetería'];
    }
    if (category.contains('natur') || category.contains('viaje')) {
      return [
        'Mirador',
        'Mochila',
        'Fogata',
        'Sendero',
        'Cascada',
        'Campamento'
      ];
    }
    if (category.contains('juego') || category.contains('gaming')) {
      return ['Control', 'Nivel', 'Equipo', 'Torneo', 'Avatar', 'Misión'];
    }
    return [
      'Karaoke',
      'La playa',
      'Cumbia',
      'Machu Picchu',
      'Pisco sour',
      'Cine'
    ];
  }

  List<String> _challengesFor(Activity? activity) {
    final category = activity?.category.toLowerCase() ?? '';
    if (category.contains('deport')) {
      return [
        'elige el calentamiento del grupo',
        'hace diez sentadillas',
        'cuenta su mejor anécdota deportiva',
        'propone el nombre de un equipo',
      ];
    }
    if (category.contains('comida') || category.contains('gastronom')) {
      return [
        'recomienda un plato que todos deberían probar',
        'describe su comida favorita sin decir su nombre',
        'elige el próximo lugar para comer',
        'cuenta su peor experiencia cocinando',
      ];
    }
    if (category.contains('natur') || category.contains('viaje')) {
      return [
        'propone una foto creativa para el grupo',
        'cuenta su viaje más memorable',
        'elige el próximo punto para explorar',
        'encuentra algo del color indicado',
      ];
    }
    return [
      'cuenta un dato curioso sobre sí mismo',
      'imita a alguien del grupo',
      'elige quién sigue y le propone un reto',
      'canta el coro de una canción',
      'cuenta su anécdota más divertida',
    ];
  }

  void _rollDice() {
    HapticFeedback.heavyImpact();
    setState(() {
      _die1 = _random.nextInt(6) + 1;
      _die2 = _random.nextInt(6) + 1;
      _rollCount++;
    });
  }

  void _startImpostor() {
    final words = _secretWordsFor(_activity);
    setState(() {
      _impostorStarted = true;
      _impostorIndex = _random.nextInt(_players);
      _secretWord = words[_random.nextInt(words.length)];
      _currentPlayer = 0;
      _revealed = false;
    });
  }

  void _newChallenge() {
    HapticFeedback.mediumImpact();
    const letters = 'ABCDEFGHIJKLMNOPRSTUV';
    final challenges = _challengesFor(_activity);
    setState(() {
      _letter = letters[_random.nextInt(letters.length)];
      _challenge = challenges[_random.nextInt(challenges.length)];
      _challengeCount++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activity = context
        .watch<AppState>()
        .activities
        .where(
          (item) => item.id == widget.activityId,
        )
        .firstOrNull;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D111B) : const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Centro de juegos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            if (activity != null)
              Text(
                activity.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
                      .animate(animation),
              child: child,
            ),
          ),
          child: SingleChildScrollView(
            key: ValueKey(_view),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: switch (_view) {
              _GameView.menu => _buildMenu(isDark, activity),
              _GameView.dice => _gameSurface(_buildDice(isDark), isDark),
              _GameView.impostor =>
                _gameSurface(_buildImpostor(isDark), isDark),
              _GameView.initial => _gameSurface(_buildInitial(isDark), isDark),
            },
          ),
        ),
      ),
    );
  }

  Widget _gameSurface(Widget child, bool isDark) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B26) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFE8EAF1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: child,
      );

  // ════════════════════════════ MENÚ ═══════════════════════════
  Widget _buildMenu(bool isDark, Activity? activity) {
    final companion = context.read<AppState>().currentUser?.companionAsset ??
        'assets/images/mascota/ELI.png';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF142B67), Color(0xFF244CA5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF142B67).withValues(alpha: 0.25),
                blurRadius: 22,
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        activity?.category.toUpperCase() ?? 'ACTIVIDAD',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Juguemos juntos',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${activity?.currentParticipants ?? 0} participantes · retos adaptados al plan',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11.5,
                          height: 1.35),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 92,
                height: 104,
                child: CompanionView(
                    asset: companion, motion: CompanionMotion.celebrate),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Recomendados para este plan',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
        const SizedBox(height: 12),
        _gameCard(
          icon: Icons.casino_rounded,
          title: 'Dados virtuales',
          subtitle: 'Decidan turnos, equipos o pequeños retos',
          meta: '2+ personas · 1 min',
          color: const Color(0xFF38BDF8),
          onTap: () => setState(() => _view = _GameView.dice),
          delay: 0,
        ),
        _gameCard(
          icon: Icons.visibility_off_rounded,
          title: 'El Impostor',
          subtitle: 'Palabras inspiradas en ${activity?.category ?? 'el plan'}',
          meta: '3–12 personas · 5 min',
          color: const Color(0xFFC084FC),
          onTap: () {
            setState(() {
              _view = _GameView.impostor;
              _impostorStarted = false;
            });
          },
          delay: 80,
        ),
        _gameCard(
          icon: Icons.shuffle_rounded,
          title: 'Reto por inicial',
          subtitle: 'Retos breves adaptados a la actividad',
          meta: '3+ personas · 3 min',
          color: const Color(0xFFFB7185),
          onTap: () => setState(() => _view = _GameView.initial),
          delay: 160,
        ),
      ],
    );
  }

  Widget _gameCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String meta,
    required Color color,
    required VoidCallback onTap,
    required int delay,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.10 : 0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(icon, color: color, size: 25),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            isDark ? const Color(0xFF94A3B8) : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      meta,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: color),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: color),
            ],
          ),
        ),
      ),
    ).animate(delay: delay.ms).fadeIn().slideX(begin: 0.08);
  }

  // ════════════════════════════ DADOS ══════════════════════════
  Widget _buildDice(bool isDark) {
    const faces = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _gameHeader(Icons.casino_rounded, 'Dados virtuales', isDark),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _dieFace(faces[_die1 - 1], isDark),
            const SizedBox(width: 18),
            _dieFace(faces[_die2 - 1], isDark),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Total: ${_die1 + _die2}',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 18),
        _primaryButton(
          label: 'Lanzar dados',
          icon: Icons.casino_rounded,
          onTap: _rollDice,
        ),
      ],
    );
  }

  Widget _dieFace(String face, bool isDark) {
    return Container(
      key: ValueKey('$face-$_rollCount'),
      width: 86,
      height: 86,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222B) : Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primaryOrange.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryOrange.withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: Text(
          face,
          style: TextStyle(
            fontSize: 60,
            height: 1,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    )
        .animate()
        .rotate(
            begin: -0.15, end: 0, duration: 450.ms, curve: Curves.easeOutBack)
        .scale(begin: const Offset(0.7, 0.7), curve: Curves.easeOutBack);
  }

  // ═══════════════════════════ IMPOSTOR ════════════════════════
  Widget _buildImpostor(bool isDark) {
    if (!_impostorStarted) {
      // Configuración: número de jugadores
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _gameHeader(Icons.visibility_off_rounded, 'El Impostor', isDark),
          const SizedBox(height: 8),
          Text(
            'Todos verán la palabra secreta, menos el impostor.\nPasen el celular y descubran quién miente.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: isDark ? const Color(0xFF94A3B8) : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _counterButton(Icons.remove_rounded, () {
                if (_players > 3) setState(() => _players--);
              }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Text(
                      '$_players',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'jugadores',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            isDark ? const Color(0xFF94A3B8) : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              _counterButton(Icons.add_rounded, () {
                if (_players < 12) setState(() => _players++);
              }),
            ],
          ),
          const SizedBox(height: 20),
          _primaryButton(
            label: 'Repartir roles',
            icon: Icons.play_arrow_rounded,
            onTap: () {
              HapticFeedback.mediumImpact();
              _startImpostor();
            },
          ),
        ],
      );
    }

    final finished = _currentPlayer >= _players;
    if (finished) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _gameHeader(Icons.visibility_off_rounded, 'El Impostor', isDark),
          const SizedBox(height: 16),
          const Text('🗣️', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 10),
          Text(
            '¡Que empiece el debate!',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hagan preguntas sobre la palabra secreta.\n¿Quién no sabe de qué hablan? 👀',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: isDark ? const Color(0xFF94A3B8) : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          _primaryButton(
            label: 'Jugar de nuevo',
            icon: Icons.refresh_rounded,
            onTap: _startImpostor,
          ),
        ],
      );
    }

    final isImpostor = _currentPlayer == _impostorIndex;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _gameHeader(Icons.visibility_off_rounded, 'El Impostor', isDark),
        const SizedBox(height: 6),
        Text(
          'Jugador ${_currentPlayer + 1} de $_players',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark ? const Color(0xFF94A3B8) : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() {
              if (_revealed) {
                _currentPlayer++;
                _revealed = false;
              } else {
                _revealed = true;
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _revealed
                    ? (isImpostor
                        ? [const Color(0xFFEF4444), const Color(0xFF991B1B)]
                        : [const Color(0xFF22C55E), const Color(0xFF15803D)])
                    : [const Color(0xFF6366F1), const Color(0xFF4338CA)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              key: ValueKey('$_currentPlayer-$_revealed'),
              children: _revealed
                  ? [
                      Text(
                        isImpostor ? '🤫' : '🤝',
                        style: const TextStyle(fontSize: 40),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isImpostor ? '¡ERES EL IMPOSTOR!' : _secretWord,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isImpostor
                            ? 'Disimula y descubre la palabra'
                            : 'Esa es la palabra secreta, shhh',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Toca para pasar al siguiente →',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]
                  : [
                      const Text('🔒', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 10),
                      const Text(
                        'Toca para revelar tu rol',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Que nadie más mire 👀',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13,
                        ),
                      ),
                    ],
            ),
          ).animate().fadeIn(duration: 250.ms),
        ),
      ],
    );
  }

  // ═══════════════════════ RETO POR INICIAL ════════════════════
  Widget _buildInitial(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _gameHeader(Icons.shuffle_rounded, 'Reto por inicial', isDark),
        const SizedBox(height: 18),
        Container(
          key: ValueKey('$_letter-$_challengeCount'),
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryOrange, Color(0xFFFF2D55)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryOrange.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Text(
              _letter,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 52,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        )
            .animate()
            .scale(begin: const Offset(0.6, 0.6), curve: Curves.easeOutBack)
            .rotate(begin: -0.08, end: 0),
        const SizedBox(height: 16),
        Text(
          _letter == '?'
              ? _challenge
              : 'Quien tenga nombre con "$_letter"\n$_challenge',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 20),
        _primaryButton(
          label: _letter == '?' ? 'Sortear letra' : 'Otra letra',
          icon: Icons.shuffle_rounded,
          onTap: _newChallenge,
        ),
      ],
    );
  }

  // ═════════════════════════ Helpers UI ════════════════════════
  Widget _gameHeader(IconData gameIcon, String title, bool isDark) {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _view = _GameView.menu);
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(gameIcon, size: 19, color: AppColors.primaryOrange),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 34), // balance visual del botón atrás
      ],
    );
  }

  Widget _counterButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.primaryOrange.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.primaryOrange.withValues(alpha: 0.35),
          ),
        ),
        child: Icon(icon, color: AppColors.primaryOrange, size: 22),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryOrange, Color(0xFFFF2D55)],
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryOrange.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 19),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
