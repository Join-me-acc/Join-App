import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Piezas comunes a los chats de la app (plan y clan).
///
/// Viven aquí para que los dos chats se vean y se comporten igual: antes
/// cada pantalla tenía su propia cabecera, caja de texto y estado vacío, y
/// se iban separando con cada cambio.

/// Cabecera del chat: volver, avatar, título con subtítulo y una acción.
class ChatHeader extends StatelessWidget {
  final Widget avatar;
  final String title;
  final String subtitle;
  final String semanticLabel;
  final VoidCallback? onTapTitle;
  final Widget? trailing;

  const ChatHeader({
    super.key,
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    this.onTapTitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 14, 10),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Volver',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Semantics(
                button: onTapTitle != null,
                label: semanticLabel,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTapTitle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        avatar,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Row(
                                children: [
                                  Icon(Icons.lock_rounded,
                                      size: 11,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.grey[500]),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Avatar cuadrado redondeado con marco degradado del color [accent].
/// Si no hay imagen, muestra la inicial de [fallbackText].
class ChatAvatar extends StatelessWidget {
  final String? imageUrl;
  final Color accent;
  final String fallbackText;

  const ChatAvatar({
    super.key,
    required this.imageUrl,
    required this.accent,
    this.fallbackText = '',
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl ?? '';
    final initial = fallbackText.trim().isEmpty
        ? '?'
        : fallbackText.trim().characters.first.toUpperCase();
    final placeholder = Center(
      child: Text(
        initial,
        style: GoogleFonts.outfit(
            fontSize: 18, fontWeight: FontWeight.w800, color: accent),
      ),
    );
    final Widget image = url.isEmpty
        ? placeholder
        : url.startsWith('http')
            ? Image.network(url,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder)
            : Image.asset(url,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);

    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          colors: [accent, accent.withValues(alpha: 0.55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: ColoredBox(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1A1F29)
              : Color.lerp(Colors.white, accent, 0.12)!,
          child: SizedBox.expand(child: image),
        ),
      ),
    );
  }
}

/// Botón de la cabecera con degradado (p. ej. "Juegos").
class ChatHeaderPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ChatHeaderPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      // La sombra va fuera del Material: dentro de un Ink se recortaba y
      // dejaba un rectángulo rosado alrededor de la píldora.
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFD7C36), Color(0xFFFF2D55)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF2D55).withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.mediumImpact();
              onTap();
            },
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(label,
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón redondo y sobrio para la cabecera (p. ej. información del clan).
class ChatHeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const ChatHeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF1A1F29) : const Color(0xFFF1F3F7),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon,
            size: 20,
            color: isDark ? Colors.white70 : const Color(0xFF475569)),
        onPressed: onTap,
      ),
    );
  }
}

/// Fondo ilustrado del chat. En oscuro se invierte para que queden trazos
/// tenues sobre el negro de la app en lugar de un velo gris.
BoxDecoration chatWallpaper(bool isDark) => BoxDecoration(
      image: DecorationImage(
        image: const AssetImage('assets/images/wallpaper/join-fondo.jpg'),
        fit: BoxFit.cover,
        opacity: isDark ? 0.05 : 0.15,
        colorFilter: isDark
            ? const ColorFilter.matrix(<double>[
                -1, 0, 0, 0, 255, //
                0, -1, 0, 0, 255, //
                0, 0, -1, 0, 255, //
                0, 0, 0, 1, 0, //
              ])
            : null,
      ),
    );

/// Caja de escritura: adjuntar dentro de la píldora y un botón de enviar que
/// sólo se enciende cuando hay algo que mandar.
class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final String hintText;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.onAttach,
    required this.onSend,
    this.hintText = 'Escribe un mensaje…',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldColor = isDark ? const Color(0xFF1A1F29) : const Color(0xFFF4F5F8);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF12161E) : Colors.white,
        border: Border(
          top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFEEF0F4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: fieldColor,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFE6E8EE)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Adjuntar foto',
                      icon: Icon(Icons.add_photo_alternate_rounded,
                          color:
                              isDark ? Colors.white60 : const Color(0xFF64748B),
                          size: 22),
                      onPressed: onAttach,
                    ),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 120),
                        child: TextField(
                          controller: controller,
                          style: GoogleFonts.outfit(
                              fontSize: 15,
                              color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            hintText: hintText,
                            hintStyle: GoogleFonts.outfit(
                                color: isDark
                                    ? Colors.white38
                                    : const Color(0xFF94A3B8),
                                fontSize: 15),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.fromLTRB(0, 13, 14, 13),
                          ),
                          minLines: 1,
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final canSend = value.text.trim().isNotEmpty;
                return Semantics(
                  button: true,
                  enabled: canSend,
                  label: 'Enviar mensaje',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: canSend
                        ? () {
                            HapticFeedback.lightImpact();
                            onSend();
                          }
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: canSend
                            ? const LinearGradient(
                                colors: [Color(0xFFFD7C36), Color(0xFFEA4E00)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight)
                            : null,
                        color: canSend ? null : fieldColor,
                        shape: BoxShape.circle,
                        boxShadow: canSend
                            ? [
                                BoxShadow(
                                    color: const Color(0xFFFD7C36)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4))
                              ]
                            : null,
                      ),
                      child: AnimatedRotation(
                        turns: canSend ? -0.08 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.send_rounded,
                            color: canSend
                                ? Colors.white
                                : (isDark
                                    ? Colors.white30
                                    : const Color(0xFFB6BDC9)),
                            size: 20),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Acción rápida del estado vacío.
class ChatEmptyAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const ChatEmptyAction(this.label, this.icon, this.onTap);
}

/// Chat sin mensajes: invita a romper el hielo en lugar de un fondo vacío.
class ChatEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final List<ChatEmptyAction> actions;
  final String securityLabel;
  final VoidCallback onSecurity;

  const ChatEmptyState({
    super.key,
    this.icon = Icons.waving_hand_rounded,
    required this.title,
    required this.message,
    required this.actions,
    required this.onSecurity,
    this.securityLabel = 'Mensajes cifrados de extremo a extremo',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF161B24) : Colors.white;
    final muted = isDark ? Colors.white60 : const Color(0xFF64748B);
    final amber = isDark ? Colors.amber[200]! : const Color(0xFFB45309);

    Widget chip(ChatEmptyAction a) => Material(
          color: const Color(0xFFFD7C36).withValues(alpha: isDark ? 0.16 : 0.1),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: a.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(a.icon, size: 17, color: const Color(0xFFEA580C)),
                  const SizedBox(width: 6),
                  Text(a.label,
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFFFDBA8C)
                              : const Color(0xFFC2410C))),
                ],
              ),
            ),
          ),
        );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              decoration: BoxDecoration(
                color: card.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFEEF0F4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFD7C36), Color(0xFFFF2D55)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 14),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                        fontSize: 14, height: 1.4, color: muted),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [for (final a in actions) chip(a)],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onSecurity,
              icon: Icon(Icons.lock_rounded, size: 14, color: amber),
              label: Text(securityLabel,
                  style: GoogleFonts.outfit(
                      fontSize: 12, fontWeight: FontWeight.w600, color: amber)),
            ),
          ],
        ),
      ),
    );
  }
}
