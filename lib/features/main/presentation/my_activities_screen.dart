import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:join_app/core/models/activity_model.dart';
import 'package:join_app/core/models/interest_model.dart';
import 'package:join_app/core/providers/app_state.dart';
import 'package:join_app/core/theme/app_colors.dart';
import 'package:intl/intl.dart';

class MyActivitiesScreen extends StatefulWidget {
  const MyActivitiesScreen({super.key});

  @override
  State<MyActivitiesScreen> createState() => _MyActivitiesScreenState();
}

class _MyActivitiesScreenState extends State<MyActivitiesScreen> with SingleTickerProviderStateMixin {
  late AnimationController _headerController;

  @override
  void initState() {
    super.initState();
    _headerController = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _headerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final myActivities = appState.myActivities;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 95,
            floating: false,
            pinned: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCollapsed = constraints.maxHeight <= kToolbarHeight + 10;
                    return FlexibleSpaceBar(
                      background: _buildHeader(),
                      titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      title: AnimatedOpacity(
                        opacity: isCollapsed ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [AppColors.primaryOrange, Color(0xFFFF2D55)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: Text(
                            'Mis Planes',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white.withValues(alpha: 0.1)
                              : AppColors.navyBlue.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.12)
                                : AppColors.navyBlue.withValues(alpha: 0.08),
                            width: 1,
                          ),
                        ),
                        child: IconButton(
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.add_rounded,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : AppColors.navyBlue,
                            size: 22,
                          ),
                          onPressed: () => context.push('/main/create'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          if (myActivities.isEmpty)
            SliverFillRemaining(child: _buildEmptyState(context))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _PremiumActivityCard(activity: myActivities[index], index: index),
                  ),
                  childCount: myActivities.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedBuilder(
      animation: _headerController,
      builder: (context, _) {
        final t = _headerController.value;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF161920).withValues(alpha: 0.82)
                : Colors.white.withValues(alpha: 0.82),
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.04),
                width: 1,
              ),
            ),
          ),
          child: Stack(
            children: [
              // Orbe decorativo muy suave en la esquina
              Positioned(
                right: -20 + t * 15,
                top: -20 + t * 10,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primaryOrange.withValues(alpha: 0.15),
                        AppColors.primaryOrange.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 80, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppColors.primaryOrange, Color(0xFFFF2D55)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryOrange.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.star_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [AppColors.primaryOrange, Color(0xFFFF2D55)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: Text(
                              'Mis Planes',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Actividades en las que eres el anfitrión',
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF94A3B8)
                              : AppColors.navyBlue.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primaryOrange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.rocket_launch_rounded, size: 48, color: AppColors.primaryOrange),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.1, 1.1), duration: 2.seconds),
          const SizedBox(height: 24),
          Text('Aún no has creado planes',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          Text(
              'Conviértete en anfitrión y reúne personas\ncon tus mismos intereses',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF94A3B8)
                      : Colors.grey[600],
                  height: 1.5)),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => context.push('/main/create'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Crear mi primer plan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 4,
              shadowColor: AppColors.primaryOrange.withValues(alpha: 0.4),
            ),
          ).animate().fadeIn(delay: 400.ms),
        ],
      ),
    );
  }
}

class _PremiumActivityCard extends StatelessWidget {
  final Activity activity;
  final int index;

  const _PremiumActivityCard({required this.activity, required this.index});

  /// La categoría se guarda como "Deportes,Fútbol": comparar el texto entero
  /// con "Deportes" fallaba y todas las tarjetas salían en naranja genérico.
  String? get _main => CategoryConstants.mainCategoryOf(activity.category);

  String? get _sub {
    final main = _main;
    if (main == null) return null;
    final subs = CategoryConstants.groups[main] ?? const <String>[];
    for (final part in activity.category.split(',')) {
      final name = part.trim();
      if (subs.contains(name)) return name;
    }
    return null;
  }

  Color get _categoryColor =>
      CategoryConstants.colors[_main] ?? AppColors.primaryOrange;

  IconData get _categoryIcon =>
      CategoryConstants.icons[_sub ?? _main] ?? Icons.category_rounded;

  String get _categoryLabel =>
      [_main, _sub].whereType<String>().join(' · ').ifEmpty(activity.category);

  /// "Hoy", "Mañana", "En 5 días" o, si ya pasó, "Hace 3 meses". El estado
  /// "Finalizado" ya lo dice la píldora de la portada.
  String get _countdown {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(activity.eventDateTime.year,
        activity.eventDateTime.month, activity.eventDateTime.day);
    final days = day.difference(today).inDays;
    if (days < 0) {
      final ago = -days;
      if (ago == 1) return 'Ayer';
      if (ago < 60) return 'Hace $ago días';
      return 'Hace ${(ago / 30).round()} meses';
    }
    if (days == 0) return 'Hoy';
    if (days == 1) return 'Mañana';
    if (days < 60) return 'En $days días';
    final months = (days / 30).round();
    return 'En $months meses';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _categoryColor;
    final isFull = activity.currentParticipants >= activity.maxParticipants;
    final finished = activity.isPast;
    final pending = context
        .watch<AppState>()
        .pendingRequests
        .where((r) => r.activityId == activity.id)
        .length;
    final occupancy = activity.maxParticipants == 0
        ? 0.0
        : (activity.currentParticipants / activity.maxParticipants)
            .clamp(0.0, 1.0);
    final surface = Theme.of(context).cardTheme.color ??
        Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final (statusText, statusColor) = finished
        ? ('Finalizado', const Color(0xFF94A3B8))
        : isFull
            ? ('Lleno', AppColors.lightOrange)
            : ('Abierto', const Color(0xFF4ADE80));

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFF041249).withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : const Color(0xFF041249).withValues(alpha: 0.07),
            blurRadius: 28,
            spreadRadius: -6,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/main/activity/${activity.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Portada con título encima ─────────────────────────
              SizedBox(
                height: 176,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    activity.imageUrl.startsWith('http')
                        ? Image.network(activity.imageUrl, fit: BoxFit.cover)
                        : Image.asset(activity.imageUrl, fit: BoxFit.cover),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0, 0.45, 1],
                          colors: [
                            Colors.black.withValues(alpha: 0.18),
                            Colors.black.withValues(alpha: 0.0),
                            Colors.black.withValues(alpha: 0.72),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 14,
                      left: 14,
                      child: _GlassPill(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(_categoryIcon,
                                  size: 12, color: Colors.white),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              _categoryLabel,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 14,
                      right: 14,
                      child: _GlassPill(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: statusColor.withValues(alpha: 0.7),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusText,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activity.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.3,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.schedule_rounded,
                                  size: 14, color: Colors.white70),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  DateFormat("EEE d 'de' MMM · HH:mm", 'es')
                                      .format(activity.eventDateTime),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
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

              // ── Ocupación y cuenta regresiva ──────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.people_alt_rounded, size: 16, color: color),
                        const SizedBox(width: 6),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: '${activity.currentParticipants}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: onSurface),
                            ),
                            TextSpan(
                              text: ' / ${activity.maxParticipants} participantes',
                              style: TextStyle(color: muted),
                            ),
                          ]),
                          style: GoogleFonts.outfit(fontSize: 13.5),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: isDark ? 0.18 : 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _countdown,
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Color.lerp(color, Colors.white, 0.35)
                                  : Color.lerp(color, Colors.black, 0.15),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: occupancy,
                        minHeight: 6,
                        color: color,
                        backgroundColor:
                            color.withValues(alpha: isDark ? 0.16 : 0.1),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Acciones ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionBtn(
                        icon: Icons.how_to_reg_rounded,
                        label: 'Solicitudes',
                        color: AppColors.skyBlue,
                        badge: pending,
                        onTap: () => context
                            .push('/main/activity/${activity.id}/requests'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionBtn(
                        icon: Icons.forum_rounded,
                        label: 'Chat',
                        color: const Color(0xFF8B5CF6),
                        onTap: () =>
                            context.push('/main/activity/${activity.id}/group'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionBtn(
                        icon: Icons.edit_rounded,
                        label: 'Editar',
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF475569),
                        onTap: () =>
                            context.push('/main/activity/${activity.id}/edit'),
                      ),
                    ),
                    // Eliminar es destructivo: va en el menú, no junto a las
                    // acciones de todos los días.
                    PopupMenuButton<String>(
                      tooltip: 'Más opciones',
                      icon: Icon(Icons.more_vert_rounded, color: muted),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      onSelected: (value) {
                        if (value == 'delete') _confirmDelete(context, activity);
                        if (value == 'view') {
                          context.push('/main/activity/${activity.id}');
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.visibility_rounded),
                            title: Text('Ver plan'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          enabled: activity.currentParticipants <= 0,
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.delete_outline_rounded,
                                color: Color(0xFFE53935)),
                            title: const Text('Eliminar plan',
                                style: TextStyle(color: Color(0xFFE53935))),
                            subtitle: activity.currentParticipants > 0
                                ? const Text('Tiene participantes')
                                : null,
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
    ).animate().fadeIn(duration: 450.ms, delay: Duration(milliseconds: 90 * index)).slideY(begin: 0.12, curve: Curves.easeOutCubic);
  }


  void _confirmDelete(BuildContext context, Activity activity) {
    HapticFeedback.heavyImpact();
    
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (ctx, a1, a2) => const SizedBox(),
      transitionBuilder: (ctx, animation, _, __) {
        final double scale = Curves.easeOutBack.transform(animation.value);
        final double opacity = Curves.easeIn.transform(animation.value);
        return Transform.scale(
          scale: scale.clamp(0.0, 1.0),
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: AlertDialog(
              backgroundColor: Theme.of(ctx).colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              elevation: 20,
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? const Color(0xFF2E1A1A)
                          : const Color(0xFFFDEDEC),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_forever_rounded,
                      color: Color(0xFFE53935),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '¿Eliminar plan?',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Esta acción no se puede deshacer. Tu plan "${activity.title}" se borrará permanentemente de Join.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? const Color(0xFF94A3B8)
                          : Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Theme.of(ctx).brightness == Brightness.dark
                                  ? const Color(0xFF2E323F)
                                  : Colors.grey.shade300,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(ctx).brightness == Brightness.dark
                                  ? const Color(0xFFE2E8F0)
                                  : Colors.grey[700],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            HapticFeedback.mediumImpact();
                            Navigator.pop(ctx);
                            
                            // Mostrar cargando
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Eliminando actividad...'),
                                duration: Duration(seconds: 1),
                              ),
                            );

                            try {
                              await context.read<AppState>().deleteActivity(activity.id);
                              
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('🗑️ Plan eliminado correctamente'),
                                    backgroundColor: Color(0xFFE53935),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error al eliminar: $e')),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE53935),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: Text(
                            'Eliminar',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int badge;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Color.lerp(color, Colors.white, 0.3)! : color;
    return Semantics(
      button: true,
      label: badge > 0 ? '$label, $badge pendientes' : label,
      excludeSemantics: true,
      child: Material(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 42,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: fg, size: 17),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: fg,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF2D55),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$badge',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Píldora de vidrio esmerilado para las etiquetas sobre la portada.
class _GlassPill extends StatelessWidget {
  final Widget child;

  const _GlassPill({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 5, 11, 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: child,
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
