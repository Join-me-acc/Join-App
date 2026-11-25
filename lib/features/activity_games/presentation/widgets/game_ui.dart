import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Piezas visuales comunes del centro de juegos.
///
/// Todos los juegos comparten fondo, tarjetas y botones para que el centro
/// se sienta como una sola cosa, teñida con el color de la categoría del
/// plan. Respetan `MediaQuery.disableAnimations` y el escalado de texto.

bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

extension GameEntrance on Widget {
  /// Entrada suave; se omite si el sistema pide reducir el movimiento.
  Widget entrance(BuildContext context, {int delayMs = 0, double dy = 0.06}) {
    if (reduceMotion(context)) return this;
    return animate(delay: delayMs.ms)
        .fadeIn(duration: 320.ms, curve: Curves.easeOutCubic)
        .slideY(begin: dy, end: 0, duration: 320.ms, curve: Curves.easeOutCubic);
  }

  /// Rebote para lo que acaba de cambiar (un dado, una letra).
  Widget pop(BuildContext context, {Object? key}) {
    if (reduceMotion(context)) return this;
    return animate(key: key is Key ? key : ValueKey(key))
        .scale(
            begin: const Offset(0.7, 0.7),
            duration: 380.ms,
            curve: Curves.easeOutBack)
        .fadeIn(duration: 200.ms);
  }
}

class GamePalette {
  final bool isDark;
  final Color accent;

  const GamePalette(this.isDark, this.accent);

  factory GamePalette.of(BuildContext context, Color accent) =>
      GamePalette(Theme.of(context).brightness == Brightness.dark, accent);

  Color get background =>
      isDark ? const Color(0xFF0D111B) : const Color(0xFFF6F7FB);
  Color get surface => isDark ? const Color(0xFF161B26) : Colors.white;
  Color get surfaceAlt =>
      isDark ? const Color(0xFF1E2431) : const Color(0xFFF1F3F8);
  Color get border => isDark ? Colors.white10 : const Color(0xFFE6E8EF);
  Color get text => isDark ? const Color(0xFFF1F5F9) : const Color(0xFF111827);
  Color get muted => isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

  /// El acento con suficiente contraste para usarlo como texto.
  Color get accentText {
    final hsl = HSLColor.fromColor(accent);
    return isDark
        ? hsl.withLightness((hsl.lightness + 0.18).clamp(0.0, 0.82)).toColor()
        : hsl.withLightness((hsl.lightness - 0.08).clamp(0.22, 1.0)).toColor();
  }

  LinearGradient get accentGradient {
    final hsl = HSLColor.fromColor(accent);
    return LinearGradient(
      colors: [
        accent,
        hsl
            .withHue((hsl.hue + 22) % 360)
            .withLightness((hsl.lightness - 0.08).clamp(0.15, 1.0))
            .toColor(),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}

/// Pantalla base de un juego.
class GameScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color accent;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottom;
  final Future<bool> Function()? onWillLeave;

  const GameScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.accent,
    required this.body,
    this.actions,
    this.bottom,
    this.onWillLeave,
  });

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, accent);
    final scaffold = Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        foregroundColor: p.text,
        actions: actions,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900)),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: p.muted),
              ),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.9, -1.1),
            radius: 1.2,
            colors: [
              accent.withValues(alpha: p.isDark ? 0.16 : 0.10),
              p.background.withValues(alpha: 0),
            ],
          ),
        ),
        child: SafeArea(top: false, child: body),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: bottom!,
            ),
    );

    if (onWillLeave == null) return scaffold;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await onWillLeave!()) navigator.pop();
      },
      child: scaffold,
    );
  }
}

/// Tarjeta principal de un juego.
class GameSurface extends StatelessWidget {
  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;

  const GameSurface({
    super.key,
    required this.child,
    required this.accent,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, accent);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.22 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Botón principal con degradado del acento. Deshabilitado si [onTap] es null.
class GameButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color accent;
  final bool busy;
  final bool secondary;

  const GameButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    required this.accent,
    this.busy = false,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, accent);
    final enabled = onTap != null && !busy;
    final fg = secondary ? p.accentText : Colors.white;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled || busy ? 1 : 0.45,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onTap!();
                  }
                : null,
            child: Ink(
              decoration: BoxDecoration(
                gradient: secondary ? null : p.accentGradient,
                color: secondary ? accent.withValues(alpha: 0.12) : null,
                borderRadius: BorderRadius.circular(18),
                border: secondary
                    ? Border.all(color: accent.withValues(alpha: 0.35))
                    : null,
                boxShadow: secondary || !enabled
                    ? null
                    : [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.32),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 54),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (busy)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: fg),
                        )
                      else if (icon != null)
                        Icon(icon, color: fg, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: fg,
                              fontSize: 15,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Etiqueta pequeña.
class GameChip extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const GameChip({super.key, required this.text, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.isDark ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: p.accentText),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: p.accentText),
            ),
          ),
        ],
      ),
    );
  }
}

/// Encabezado de sección dentro de un juego.
class GameSectionTitle extends StatelessWidget {
  final String text;
  final Color accent;
  final Widget? trailing;

  const GameSectionTitle(this.text,
      {super.key, required this.accent, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, accent);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900, color: p.text),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Avatar circular con iniciales de respaldo.
class GameAvatar extends StatelessWidget {
  final String name;
  final String imageUrl;
  final double size;
  final Color accent;
  final bool online;

  const GameAvatar({
    super.key,
    required this.name,
    this.imageUrl = '',
    this.size = 40,
    required this.accent,
    this.online = false,
  });

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, accent);
    final hasImage = imageUrl.startsWith('http');
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.18),
              image: hasImage
                  ? DecorationImage(
                      image: NetworkImage(imageUrl), fit: BoxFit.cover)
                  : null,
            ),
            alignment: Alignment.center,
            child: hasImage
                ? null
                : Text(
                    _initials,
                    style: TextStyle(
                        fontSize: size * 0.36,
                        fontWeight: FontWeight.w900,
                        color: p.accentText),
                  ),
          ),
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(color: p.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Botón redondo para contadores (+ / −).
class GameRoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color accent;
  final String semanticLabel;
  final double size;

  const GameRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.accent,
    required this.semanticLabel,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, accent);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: accent.withValues(alpha: p.isDark ? 0.18 : 0.11),
        shape: CircleBorder(
            side: BorderSide(color: accent.withValues(alpha: 0.35))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon,
                color: onTap == null ? p.muted : p.accentText, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Contador "N jugadores" con botones + y −.
class GameCounter extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final String label;
  final Color accent;
  final ValueChanged<int> onChanged;

  const GameCounter({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, accent);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GameRoundButton(
          icon: Icons.remove_rounded,
          accent: accent,
          semanticLabel: 'Quitar uno',
          onTap: value > min ? () => onChanged(value - 1) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Semantics(
            liveRegion: true,
            label: '$value $label',
            excludeSemantics: true,
            child: Column(
              children: [
                Text('$value',
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: p.text)),
                Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
              ],
            ),
          ),
        ),
        GameRoundButton(
          icon: Icons.add_rounded,
          accent: accent,
          semanticLabel: 'Añadir uno',
          onTap: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

/// Mensaje vacío o de error, con acción opcional.
class GameEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color accent;
  final String? actionLabel;
  final VoidCallback? onAction;

  const GameEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final p = GamePalette.of(context, accent);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: p.accentText),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900, color: p.text)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.4, color: p.muted)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              GameButton(
                  label: actionLabel!,
                  onTap: onAction,
                  accent: accent,
                  icon: Icons.refresh_rounded),
            ],
          ],
        ),
      ),
    );
  }
}
