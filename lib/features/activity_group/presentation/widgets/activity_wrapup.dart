import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:join_app/core/models/activity_lifecycle.dart';
import 'package:join_app/core/models/activity_model.dart';
import 'package:join_app/core/providers/app_state.dart';
import 'package:join_app/features/activity_games/data/activity_game_repository.dart';

/// Piezas del cierre de un plan dentro de su chat: el aviso de que terminó,
/// la barra de chat cerrado y la creación de un clan con el grupo.

String _closingDate(DateTime utc) =>
    DateFormat("EEEE d 'a las' HH:mm", 'es').format(utc.toLocal());

/// Tarjeta que aparece arriba del chat cuando el plan terminó y el chat
/// sigue abierto sus 2 días de gracia.
class ActivityWrapUpBanner extends StatelessWidget {
  final Activity activity;
  final bool needsRating;
  final VoidCallback onRate;
  final VoidCallback onMural;
  final VoidCallback onClan;

  const ActivityWrapUpBanner({
    super.key,
    required this.activity,
    required this.needsRating,
    required this.onRate,
    required this.onMural,
    required this.onClan,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final left = activity.chatClosesAt.difference(DateTime.now().toUtc());
    final urgent = left.inHours < 24;
    final accent = urgent ? const Color(0xFFEF4444) : const Color(0xFF8B5CF6);
    final text = Theme.of(context).colorScheme.onSurface;
    final muted = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Semantics(
      container: true,
      liveRegion: urgent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B24) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: isDark ? 0.15 : 0.1),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                      urgent
                          ? Icons.hourglass_bottom_rounded
                          : Icons.celebration_rounded,
                      size: 19,
                      color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('El plan terminó',
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: text)),
                      Text(
                        'Este chat se cierra ${describeTimeLeft(left)} '
                        '(${_closingDate(activity.chatClosesAt)}).',
                        style: GoogleFonts.outfit(
                            fontSize: 12.5, height: 1.3, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (needsRating)
                  _WrapUpChip(
                      icon: Icons.star_rounded,
                      label: 'Calificar',
                      color: const Color(0xFFF59E0B),
                      onTap: onRate),
                _WrapUpChip(
                    icon: Icons.photo_library_rounded,
                    label: 'Mural de recuerdos',
                    color: const Color(0xFFEC4899),
                    onTap: onMural),
                _WrapUpChip(
                    icon: Icons.shield_rounded,
                    label: 'Crear clan con el grupo',
                    color: const Color(0xFFFD7C36),
                    onTap: onClan),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WrapUpChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _WrapUpChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Color.lerp(color, Colors.white, 0.3)! : color;
    return Material(
      color: color.withValues(alpha: isDark ? 0.16 : 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.outfit(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sustituye a la caja de escritura cuando el chat ya se cerró.
class ClosedChatBar extends StatelessWidget {
  final Activity activity;
  final VoidCallback onMural;
  final VoidCallback onClan;

  const ClosedChatBar({
    super.key,
    required this.activity,
    required this.onMural,
    required this.onClan,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white60 : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_clock_rounded, size: 16, color: muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Este chat se cerró ${DateFormat("d 'de' MMMM", 'es').format(activity.chatClosesAt.toLocal())}. '
                    'Puedes leerlo, pero ya no escribir.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontSize: 12.5, color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onMural,
                    icon: const Icon(Icons.photo_library_rounded, size: 18),
                    label: const Text('Mural'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onClan,
                    icon: const Icon(Icons.shield_rounded, size: 18),
                    label: const Text('Seguir en un clan'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFD7C36),
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Crea un clan con la gente del plan para que sigan en contacto cuando el
/// chat se cierre. Pide confirmar el nombre y lleva al chat del clan nuevo.
Future<void> createClanFromActivity(
    BuildContext context, Activity activity) async {
  final appState = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final me = appState.currentUser?.id;

  List<String> memberIds;
  try {
    final members =
        await ActivityGameRepository().fetchMembers(activity.id);
    memberIds = [
      for (final m in members)
        if (m.userId != me) m.userId
    ];
  } catch (_) {
    memberIds = [];
  }
  if (!context.mounted) return;

  final controller = TextEditingController(text: activity.title);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Crear clan con el grupo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            memberIds.isEmpty
                ? 'Por ahora sólo estarás tú; podrás invitar a otros desde el clan.'
                : 'Se añadirá a ${memberIds.length} ${memberIds.length == 1 ? 'persona' : 'personas'} del plan. '
                    'El clan no se cierra: es para seguir en contacto.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nombre del clan'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Crear clan')),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.isEmpty) return;

  final ok = await appState.createClan(name, memberUserIds: memberIds);
  if (!ok) {
    messenger.showSnackBar(SnackBar(
        content: Text(appState.error ?? 'No se pudo crear el clan.')));
    return;
  }
  final clan = appState.userClans.first;
  messenger.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    content: Text('Clan «${clan.name}» creado'),
    action: SnackBarAction(
      label: 'Abrir',
      onPressed: () => router.push('/clan/${clan.id}/chat', extra: clan),
    ),
  ));
}
