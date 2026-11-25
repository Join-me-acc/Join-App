import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:join_app/core/services/notification_service.dart';
import 'package:join_app/core/theme/app_colors.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:google_fonts/google_fonts.dart';

/// Pantalla de Notificaciones — conectada al backend real
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _notifications = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications({bool refresh = false}) async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final list =
          await NotificationService.fetchNotifications(forceRefresh: refresh);
      if (mounted) {
        setState(() {
          _notifications = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _markAllAsRead() async {
    await NotificationService.markAllAsRead();
    setState(() {
      _notifications = NotificationService.getNotifications();
    });
  }

  Future<void> _markAsRead(String id) async {
    await NotificationService.markAsRead(id);
    setState(() {
      _notifications = NotificationService.getNotifications();
    });
  }

  IconData _iconFor(NotificationType type) => switch (type) {
        NotificationType.joinRequest      => Icons.person_add_rounded,
        NotificationType.acceptedToGroup  => Icons.check_circle_rounded,
        NotificationType.activityReminder => Icons.alarm_rounded,
        NotificationType.newActivity      => Icons.auto_awesome_rounded,
        NotificationType.newMessage       => Icons.chat_bubble_rounded,
        NotificationType.socialJoin       => Icons.group_add_rounded,
        NotificationType.activityEnded    => Icons.star_rounded,
        NotificationType.chatClosing      => Icons.hourglass_bottom_rounded,
      };

  Color _colorFor(NotificationType type) => switch (type) {
        NotificationType.joinRequest      => const Color(0xFF3B82F6),
        NotificationType.acceptedToGroup  => const Color(0xFF16A34A),
        NotificationType.activityReminder => const Color(0xFFF59E0B),
        NotificationType.newActivity      => AppColors.primaryOrange,
        NotificationType.newMessage       => const Color(0xFF8B5CF6),
        NotificationType.socialJoin       => const Color(0xFF0EA5E9),
        NotificationType.activityEnded    => const Color(0xFFEAB308),
        NotificationType.chatClosing      => const Color(0xFFEF4444),
      };

  /// Adónde lleva cada aviso.
  String _routeFor(AppNotification n) {
    final id = n.activityId;
    return switch (n.type) {
      NotificationType.joinRequest => '/main/activity/$id/requests',
      NotificationType.acceptedToGroup ||
      NotificationType.newMessage ||
      NotificationType.chatClosing =>
        '/main/activity/$id/group',
      // La pantalla de calificar ya deriva al mural si es del organizador
      // o si ya calificó.
      NotificationType.activityEnded => '/main/activity/$id/feedback',
      _ => '/main/activity/$id',
    };
  }

  /// "Hoy", "Esta semana" o "Anteriores".
  static String _sectionOf(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Hoy';
    if (diff < 7) return 'Esta semana';
    return 'Anteriores';
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        color: AppColors.primaryOrange,
        onRefresh: () => _loadNotifications(refresh: true),
        child: CustomScrollView(
          slivers: [
            // ── AppBar Premium ──────────────────────────────────
            SliverAppBar(
              pinned: true,
              expandedHeight: 110,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF161920)
                        : const Color(0xFFF5F7FB),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_back_ios_rounded,
                      color: Theme.of(context).colorScheme.onSurface, size: 16),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                if (unreadCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton.icon(
                      onPressed: _markAllAsRead,
                      icon: const Icon(Icons.done_all_rounded,
                          size: 16, color: AppColors.primaryOrange),
                      label: const Text(
                        'Leer todo',
                        style: TextStyle(
                          color: AppColors.primaryOrange,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                title: Row(
                  children: [
                    Text(
                      'Notificaciones',
                      style: GoogleFonts.outfit(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryOrange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Contenido ───────────────────────────────────────
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryOrange,
                    strokeWidth: 2.5,
                  ),
                ),
              )
            else if (_hasError)
              SliverFillRemaining(
                child: _buildErrorState(),
              )
            else if (_notifications.isEmpty)
              SliverFillRemaining(
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final notif = _notifications[index];
                      final section = _sectionOf(notif.timestamp);
                      final showHeader = index == 0 ||
                          _sectionOf(_notifications[index - 1].timestamp) !=
                              section;
                      final card = _NotificationCard(
                        notification: notif,
                        onTap: () async {
                          // El router se resuelve antes del await; el context de
                          // este item puede dejar de estar montado al volver.
                          final router = GoRouter.of(context);
                          await _markAsRead(notif.id);
                          if (!mounted || notif.activityId == null) return;
                          router.push(_routeFor(notif));
                        },
                        iconData: _iconFor(notif.type),
                        color: _colorFor(notif.type),
                      ).animate().fadeIn(
                            duration: 300.ms,
                            delay: (index.clamp(0, 10) * 35).ms,
                          );
                      if (!showHeader) return card;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                                4, index == 0 ? 0 : 14, 4, 10),
                            child: Text(
                              section,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white54
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                          card,
                        ],
                      );
                    },
                    childCount: _notifications.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryOrange.withValues(alpha: 0.1),
                  AppColors.primaryOrange.withValues(alpha: 0.04),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 56,
              color: AppColors.primaryOrange,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Sin notificaciones',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Aquí aparecerán las solicitudes y\nnovedades de tus actividades',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF94A3B8)
                  : Colors.grey[500],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Sin conexión',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            'No se pudieron cargar las notificaciones',
            style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF94A3B8)
                    : Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _loadNotifications(refresh: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reintentar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  Widget de tarjeta de notificación premium
// ══════════════════════════════════════════════════════════════
class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final IconData iconData;
  final Color color;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.iconData,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isRead = notification.isRead;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: '${isRead ? '' : 'No leída. '}${notification.title}. '
            '${notification.message}',
        excludeSemantics: true,
        child: Material(
          color: isDark ? const Color(0xFF161B24) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isRead
                      ? (isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFEEF0F4))
                      : color.withValues(alpha: 0.35),
                ),
                // Las no leídas llevan un tinte del color de su tipo.
                gradient: isRead
                    ? null
                    : LinearGradient(
                        colors: [
                          color.withValues(alpha: isDark ? 0.12 : 0.07),
                          color.withValues(alpha: 0),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(iconData, color: color, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                notification.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontWeight: isRead
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                  fontSize: 14.5,
                                  height: 1.25,
                                  color: onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              timeago.format(notification.timestamp,
                                  locale: 'es_short'),
                              style: GoogleFonts.outfit(
                                  fontSize: 11.5, color: muted),
                            ),
                            if (!isRead) ...[
                              const SizedBox(width: 6),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: color, shape: BoxShape.circle),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (notification.message.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            notification.message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                                fontSize: 13.5, height: 1.35, color: muted),
                          ),
                        ],
                        if (notification.activityTitle != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.event_rounded,
                                    size: 12, color: color),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    notification.activityTitle!,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: color),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
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
}
