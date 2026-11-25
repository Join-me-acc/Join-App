import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:join_app/core/providers/app_state.dart';
import 'package:join_app/core/theme/app_colors.dart';

/// Transición breve entre el splash nativo y la aplicación.
/// El logo se muestra directamente, sin tarjetas ni contenido promocional.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _motionController;
  bool _saliendo = false;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _intentarSalir();
      })
      ..forward();
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _introController.dispose();
    _motionController.dispose();
    super.dispose();
  }

  void _intentarSalir() {
    if (_saliendo || !mounted || !_introController.isCompleted) return;
    final appState = context.read<AppState>();
    if (!appState.isInitialized) return;

    _saliendo = true;
    context.go(_destino(appState));
  }

  static String _destino(AppState appState) {
    if (!appState.isLoggedIn) return '/login';
    if (!(appState.currentUser?.setupCompleted ?? false)) return '/onboarding';
    return '/main';
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (appState.isInitialized && _introController.isCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _intentarSalir());
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : AppColors.navyBlue;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090D18) : Colors.white,
      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _introController,
              _motionController,
            ]),
            builder: (context, child) {
              final intro = Curves.easeOutBack.transform(
                _introController.value,
              );
              final wave = math.sin(_motionController.value * math.pi * 2);

              return Opacity(
                opacity: Curves.easeOut.transform(_introController.value),
                child: Transform.translate(
                  offset: Offset(0, wave * 5),
                  child: Transform.rotate(
                    angle: (1 - intro) * -0.10 + wave * 0.008,
                    child: Transform.scale(
                      scale: 0.68 + (intro * 0.32) + (wave * 0.012),
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/join.png',
                  width: 176,
                  height: 176,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: 152,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: AppColors.primaryOrange.withValues(
                        alpha: isDark ? 0.16 : 0.11,
                      ),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primaryOrange,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  appState.isInitialized ? 'Todo listo' : 'Cargando…',
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.58),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
