import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:join_app/core/location/activity_distance.dart';
import 'package:join_app/core/providers/app_state.dart';
import 'package:join_app/core/models/activity_model.dart';
import 'package:join_app/core/theme/app_colors.dart';
import 'package:join_app/core/models/interest_model.dart';
import 'package:join_app/core/widgets/user_avatar.dart';
import 'package:intl/intl.dart';
import 'package:join_app/core/models/join_request_model.dart';

class ActivityCard extends StatefulWidget {
  final Activity activity;
  final VoidCallback onTap;
  final bool isOrganizer;

  const ActivityCard({
    super.key,
    required this.activity,
    required this.onTap,
    this.isOrganizer = false,
  });

  @override
  State<ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<ActivityCard> {
  bool _pressed = false;

  String get _primaryCategory =>
      widget.activity.category.split(',').first.trim();

  // Color e icono salen de CategoryConstants: antes estaban copiados aquí con
  // un switch de las cinco categorías originales, así que cualquier categoría
  // nueva se quedaba sin su color.
  Color get _categoryColor =>
      CategoryConstants.colors[_primaryCategory] ?? AppColors.primaryOrange;

  IconData get _categoryIcon =>
      CategoryConstants.icons[_primaryCategory] ?? Icons.category_rounded;

  String get _dateLabel {
    final dt = widget.activity.eventDateTime;
    final now = DateTime.now();
    final diff = DateTime.utc(dt.year, dt.month, dt.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
    if (diff == 0) {
      return '¡Hoy, ${DateFormat('HH:mm').format(dt)}!';
    } else if (diff == 1) {
      return 'Mañana ${DateFormat('HH:mm').format(dt)}';
    } else if (diff > 1 && diff < 7) {
      return '${_dayName(dt.weekday)}, ${DateFormat('dd MMM').format(dt)}';
    }
    return DateFormat('dd MMM · HH:mm').format(dt);
  }

  String _dayName(int weekday) {
    const days = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return days[weekday];
  }

  @override
  Widget build(BuildContext context) {
    final slotsLeft = widget.activity.remainingSpots;
    final isFull = !widget.activity.hasAvailableSpots;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        transform: Matrix4.identity()
          ..scaleByDouble(
              _pressed ? 0.98 : 1.0, _pressed ? 0.98 : 1.0, 1.0, 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ??
              Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: _pressed
              ? []
              : [
                  BoxShadow(
                    color: _categoryColor.withValues(alpha: 0.05),
                    blurRadius: 14,
                    spreadRadius: 0,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── IMAGEN HERO ────────────────────────────────────
              _buildImageSection(isFull, slotsLeft),

              // ── CONTENIDO ─────────────────────────────────────
              _buildInfoSection(),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 500.ms)
        .slideY(begin: 0.08, curve: Curves.easeOutCubic);
  }

  static const double _coverHeight = 150;

  /// Portada de la actividad, tolerante a que no haya imagen o a que falle.
  ///
  /// Una actividad sin portada —creada por un seed, una migración o desde
  /// fuera de la app— hacía reventar la tarjeta con "Unable to load asset".
  Widget _buildCoverImage() {
    final url = widget.activity.imageUrl;
    if (url.isEmpty) return _coverPlaceholder();

    if (url.startsWith('http')) {
      return Image.network(
        url,
        height: _coverHeight,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _coverPlaceholder(),
      );
    }

    return Image.asset(
      url,
      height: _coverHeight,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _coverPlaceholder(),
    );
  }

  /// Relleno con el color e icono de la categoría, para que la tarjeta
  /// mantenga su forma aunque no haya foto.
  Widget _coverPlaceholder() {
    return Container(
      height: _coverHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _categoryColor.withValues(alpha: 0.35),
            _categoryColor.withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        CategoryConstants.icons[_primaryCategory] ?? Icons.event_rounded,
        size: 56,
        color: Colors.white.withValues(alpha: 0.85),
      ),
    );
  }

  Widget _buildImageSection(bool isFull, int slotsLeft) {
    return Stack(children: [
      Hero(
          tag: 'activity-image-${widget.activity.id}',
          child: _buildCoverImage()),
      Positioned.fill(
          child: DecoratedBox(
              decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.18),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.55)
            ],
            stops: const [
              0,
              0.45,
              1
            ]),
      ))),
      Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: _Badge(
                        icon: _categoryIcon,
                        label: _primaryCategory,
                        color: _categoryColor,
                        style: _BadgeStyle.filled))),
            const SizedBox(width: 8),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  Text(DateFormat('dd').format(widget.activity.eventDateTime),
                      style: TextStyle(
                          fontSize: 22,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 3),
                  Text(
                      DateFormat('MMM', 'es')
                          .format(widget.activity.eventDateTime)
                          .toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _categoryColor)),
                ])),
          ])),
      Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: Row(children: [
            const Icon(Icons.schedule_rounded, color: Colors.white, size: 14),
            const SizedBox(width: 5),
            Expanded(
                child: Text(_dateLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700))),
            Text(
                isFull
                    ? 'Completo'
                    : '$slotsLeft ${slotsLeft == 1 ? 'cupo libre' : 'cupos libres'}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ])),
    ]);
  }

  Widget _buildInfoSection() {
    final activity = widget.activity;
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();
    final status = appState.getMyRequestStatus(activity.id);
    final organizer = widget.isOrganizer ||
        (appState.currentUser?.id == activity.organizerId);
    final action = organizer
        ? 'Administrar'
        : status == JoinRequestStatus.accepted
            ? 'Participante'
            : status == JoinRequestStatus.pending
                ? 'Pendiente'
                : 'Ver plan';
    final distance = activityDistanceKm(activity, appState.currentPosition);
    final distanceLabel = distance == null ? null : formatDistanceKm(distance);
    return Padding(
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(activity.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 20,
                    height: 1.15,
                    letterSpacing: -0.5,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface)),
            const SizedBox(height: 7),
            Row(children: [
              Icon(Icons.location_on_outlined,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(
                      activity.locationName.isNotEmpty
                          ? activity.locationName
                          : activity.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant))),
              if (distanceLabel != null) ...[
                const SizedBox(width: 8),
                Text(distanceLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _categoryColor)),
              ],
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _InfoChip(
                  icon: Icons.people_outline_rounded,
                  label:
                      '${activity.currentParticipants}/${activity.maxParticipants} personas'),
              _InfoChip(
                  icon: Icons.person_outline_rounded, label: activity.ageRange),
            ]),
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                    height: 1,
                    color: theme.dividerColor.withValues(alpha: 0.10))),
            Row(children: [
              UserAvatar(
                  imageUrl: activity.organizerImageUrl,
                  name: activity.organizerName,
                  radius: 15),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(activity.organizerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface)),
                    Text(
                        activity.organizerRating > 0
                            ? '★ ${activity.organizerRating.toStringAsFixed(1)} · ${activity.organizerActivities} eventos'
                            : '${activity.organizerActivities} ${activity.organizerActivities == 1 ? 'evento organizado' : 'eventos organizados'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ])),
              const SizedBox(width: 8),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(action,
                      style: TextStyle(
                          color: theme.colorScheme.surface,
                          fontSize: 12,
                          fontWeight: FontWeight.w700))),
            ]),
          ],
        ));
  }
}

// ── Badge premium ─────────────────────────────────────────────
enum _BadgeStyle { filled }

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final _BadgeStyle style;

  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final isFilled = style == _BadgeStyle.filled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isFilled ? color : Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isFilled
              ? Colors.transparent
              : Colors.white.withValues(alpha: 0.3),
        ),
        boxShadow: isFilled
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info chip ─────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222B) : const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? const Color(0xFF2E323F) : Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 13,
              color: isDark ? const Color(0xFF94A3B8) : Colors.grey[600]),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFE2E8F0) : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
