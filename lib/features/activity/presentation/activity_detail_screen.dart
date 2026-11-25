import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:join_app/core/providers/app_state.dart';
import 'package:join_app/features/activity/presentation/widgets/activity_not_found.dart';
import 'package:join_app/core/models/activity_model.dart';
import 'package:join_app/core/models/join_request_model.dart';
import 'package:join_app/core/theme/app_colors.dart';
import 'package:join_app/core/widgets/user_avatar.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google_maps;
import 'package:url_launcher/url_launcher.dart';
import 'package:join_app/core/models/interest_model.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:join_app/core/widgets/companion_view.dart';
import 'package:join_app/core/location/activity_distance.dart';
import 'package:join_app/core/models/activity_lifecycle.dart';

class ActivityDetailScreen extends StatefulWidget {
  final String activityId;

  const ActivityDetailScreen({super.key, required this.activityId});

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  JoinRequestStatus? userRequestStatus;
  JoinRequest? userRequest;
  late final ScrollController _scrollController;
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    userRequestStatus = null;
    userRequest = null;
    _scrollController = ScrollController()
      ..addListener(() {
        setState(() {
          _scrollOffset = _scrollController.offset;
        });
      });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final activity =
        appState.activities.where((a) => a.id == widget.activityId).firstOrNull;
    if (activity == null) return const ActivityNotFound();

    final currentUserId = context.read<AppState>().currentUser?.id;
    final isOrganizer =
        currentUserId != null && activity.organizerId == currentUserId;
    final currentStatus =
        userRequestStatus ?? appState.getMyRequestStatus(widget.activityId);
    final isAccepted =
        isOrganizer || currentStatus == JoinRequestStatus.accepted;
    final distanceKm =
        activityDistanceKm(activity, appState.currentPosition);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Premium Parallax Sliver App Bar
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                stretch: true,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                surfaceTintColor: Colors.transparent,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 12.0),
                  child: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF161920).withValues(alpha: 0.85)
                            : Colors.white.withValues(alpha: 0.85),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back_rounded,
                          color: Theme.of(context).colorScheme.onSurface),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/main');
                        }
                      },
                    ),
                  ),
                ),
                actions: isOrganizer
                    ? [
                        CircleAvatar(
                          backgroundColor: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? const Color(0xFF161920).withValues(alpha: 0.85)
                              : Colors.white.withValues(alpha: 0.85),
                          child: IconButton(
                            icon: const Icon(Icons.edit_rounded,
                                color: Colors.blue),
                            onPressed: () => context
                                .push('/main/activity/${activity.id}/edit'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          backgroundColor: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? const Color(0xFF161920).withValues(alpha: 0.85)
                              : Colors.white.withValues(alpha: 0.85),
                          child: IconButton(
                            icon: const Icon(Icons.people_alt_rounded,
                                color: AppColors.primaryOrange),
                            onPressed: () => context
                                .push('/main/activity/${activity.id}/requests'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ]
                    : null,
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [
                    StretchMode.zoomBackground,
                  ],
                  background: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(32),
                      bottomRight: Radius.circular(32),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned(
                          top: _scrollOffset > 0 ? -_scrollOffset * 0.32 : 0,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Hero(
                            tag: 'activity-image-${activity.id}',
                            child: activity.imageUrl.startsWith('http')
                                ? Image.network(
                                    activity.imageUrl,
                                    fit: BoxFit.cover,
                                  )
                                : Image.asset(
                                    activity.imageUrl,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        // Elegante gradiente inferior negro a transparente
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.65),
                                  Colors.black.withValues(alpha: 0.25),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.5, 0.95],
                              ),
                            ),
                          ),
                        ),
                        // Info Overpuesta en Glassmorphism
                        Positioned(
                          bottom: 36,
                          left: 20,
                          right: 20,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: BackdropFilter(
                              filter:
                                  ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 20),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.16),
                                      Colors.white.withValues(alpha: 0.04),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.24),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: activity.category
                                          .split(',')
                                          .map((cat) {
                                        final cleanCat = cat.trim();
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _getCategoryColor(cleanCat),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(_getCategoryIcon(cleanCat),
                                                  size: 12,
                                                  color: Colors.white),
                                              const SizedBox(width: 6),
                                              Text(
                                                cleanCat,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                    letterSpacing: 0.5),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      activity.title,
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        height: 1.15,
                                        letterSpacing: -0.4,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.45),
                                            blurRadius: 12,
                                            offset: const Offset(0, 2),
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
                      ],
                    ),
                  ),
                ),
              ),

              // Contenido principal
              SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Organizador Row Premium
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardTheme.color ??
                                Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: AppColors.primaryOrange.withValues(
                                  alpha: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? 0.25
                                      : 0.12),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.black.withValues(alpha: 0.2)
                                    : const Color(0xFF041249)
                                        .withValues(alpha: 0.04),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                // Micro-interacción: click en organizador
                                HapticFeedback.selectionClick();
                              },
                              borderRadius: BorderRadius.circular(24),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: AppColors.primaryOrange,
                                                width: 2),
                                          ),
                                          child: UserAvatar(
                                            imageUrl:
                                                activity.organizerImageUrl,
                                            name: activity.organizerName,
                                            radius: 24,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Organizado por',
                                            style: GoogleFonts.outfit(
                                                fontSize: 10,
                                                color: Theme.of(context)
                                                            .brightness ==
                                                        Brightness.dark
                                                    ? const Color(0xFF94A3B8)
                                                    : Colors.grey[600],
                                                fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Text(
                                                activity.organizerName,
                                                style: GoogleFonts.outfit(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurface),
                                              ),
                                              const SizedBox(width: 5),
                                              const Icon(Icons.verified,
                                                  size: 16, color: Colors.blue),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.star_rounded,
                                                  size: 16,
                                                  color: Colors.amber),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${activity.organizerRating}',
                                                style: GoogleFonts.outfit(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11.5),
                                              ),
                                              Text(
                                                ' (${activity.organizerActivities} planes)',
                                                style: GoogleFonts.outfit(
                                                    color: Theme.of(context)
                                                                .brightness ==
                                                            Brightness.dark
                                                        ? const Color(
                                                            0xFF94A3B8)
                                                        : Colors.grey[500],
                                                    fontSize: 10.5),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white.withValues(alpha: 0.35)
                                          : AppColors.navyBlue
                                              .withValues(alpha: 0.35),
                                      size: 24,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Stats Grid Premium
                        GridView.count(
                          padding: EdgeInsets.zero,
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: 2.2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          children: [
                            _PremiumStatCard(
                              icon: Icons.calendar_today_rounded,
                              label: 'Fecha',
                              value:
                                  '${activity.eventDateTime.day}/${activity.eventDateTime.month}',
                              color: Colors.blue,
                            ),
                            _PremiumStatCard(
                              icon: Icons.group_rounded,
                              label: 'Participantes',
                              value:
                                  '${activity.currentParticipants}/${activity.maxParticipants}',
                              color: AppColors.primaryOrange,
                            ),
                            _PremiumStatCard(
                              icon: Icons.location_on_rounded,
                              label: 'Distancia',
                              value: distanceKm == null
                                  ? 'Sin ubicación'
                                  : formatDistanceKm(distanceKm),
                              color: Colors.green,
                            ),
                            _PremiumStatCard(
                              icon: Icons.person_add_alt_1_rounded,
                              label: 'Edades',
                              value: activity.ageRange,
                              color: Colors.purple,
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : AppColors.navyBlue
                                        .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.info_outline_rounded,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : AppColors.navyBlue,
                                  size: 20),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Acerca del plan',
                              style: GoogleFonts.outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          activity.description,
                          style: GoogleFonts.outfit(
                            fontSize: 14.5,
                            height: 1.6,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFFE2E8F0)
                                    : const Color(0xFF2D3748),
                          ),
                        ),

                        // Fichas de Aportes Necesarios
                        if (activity.contributions.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.shopping_bag_rounded,
                                    color: Colors.purple, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Aportes para llevar',
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardTheme.color ??
                                  Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: Colors.purple.withValues(
                                      alpha: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? 0.25
                                          : 0.12),
                                  width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.purple.withValues(alpha: 0.03),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              children: activity.contributions.map((c) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8.0),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.green
                                              .withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.check_rounded,
                                            color: Colors.green, size: 14),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          c,
                                          style: GoogleFonts.outfit(
                                            fontSize: 15,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],

                        // Recomendaciones de Hennessy
                        if (activity.suggestions.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryOrange
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                    Icons.tips_and_updates_rounded,
                                    color: AppColors.primaryOrange,
                                    size: 20),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Recomendaciones',
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.primaryOrange
                                  .withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: AppColors.primaryOrange
                                      .withValues(alpha: 0.15),
                                  width: 1.5),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? const Color(0xFF0A0D14)
                                            : Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    CompanionView(
                                      asset: context
                                              .watch<AppState>()
                                              .currentUser
                                              ?.companionAsset ??
                                          'assets/images/mascota/ELI.png',
                                      width: 40,
                                      height: 40,
                                      portrait: true,
                                      motion: CompanionMotion.nod,
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: activity.suggestions.map((s) {
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8.0),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Padding(
                                              padding: EdgeInsets.only(top: 2),
                                              child: Icon(Icons.pets_rounded,
                                                  size: 16,
                                                  color:
                                                      AppColors.primaryOrange),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                s,
                                                style: GoogleFonts.outfit(
                                                  fontSize: 14.5,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface,
                                                  fontWeight: FontWeight.w500,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 32),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.navyBlue.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.location_on_outlined,
                                  color: AppColors.navyBlue, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Ubicación',
                              style: GoogleFonts.outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Premium Map Design (Real si es aceptado, blur si no)
                        if (isAccepted &&
                            activity.latitude != null &&
                            activity.longitude != null) ...[
                          if (activity.hasSeparateMeetingPoint) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? const Color(0xFF1E222B)
                                    : Colors.grey[50],
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? const Color(0xFF2E323F)
                                        : Colors.grey.shade200),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryOrange
                                              .withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                            Icons.directions_run_rounded,
                                            color: AppColors.primaryOrange,
                                            size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              '1. Punto de Encuentro Previo',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              activity.meetingLocationName
                                                      .isNotEmpty
                                                  ? activity.meetingLocationName
                                                  : 'Punto de encuentro',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 16),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        width: 2,
                                        height: 20,
                                        color: AppColors.primaryOrange
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppColors.navyBlue
                                              .withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                            Icons.sports_score_rounded,
                                            color: AppColors.navyBlue,
                                            size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              '2. Lugar de la Actividad',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              activity.locationName.isNotEmpty
                                                  ? activity.locationName
                                                  : activity.location,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? const Color(0xFF1E222B)
                                    : Colors.grey[50],
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? const Color(0xFF2E323F)
                                        : Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_rounded,
                                      color: AppColors.primaryOrange, size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      activity.locationName.isNotEmpty
                                          ? activity.locationName
                                          : activity.location,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: SizedBox(
                              height: 220,
                              child: IgnorePointer(
                                ignoring: true,
                                child: _GoogleActivityMap(activity: activity),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 16.0),
                            child: SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final lat =
                                      activity.hasSeparateMeetingPoint &&
                                              activity.meetingLatitude != null
                                          ? activity.meetingLatitude
                                          : activity.latitude;
                                  final lng =
                                      activity.hasSeparateMeetingPoint &&
                                              activity.meetingLongitude != null
                                          ? activity.meetingLongitude
                                          : activity.longitude;
                                  final url =
                                      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
                                  if (await canLaunchUrl(Uri.parse(url))) {
                                    await launchUrl(Uri.parse(url),
                                        mode: LaunchMode.externalApplication);
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor:
                                      Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : AppColors.navyBlue,
                                  side: BorderSide(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? const Color(0xFF2E323F)
                                        : Colors.grey.shade300,
                                  ),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                                icon: const Icon(Icons.map_rounded,
                                    color: Colors.blue),
                                label: Text(
                                  activity.hasSeparateMeetingPoint
                                      ? 'Cómo llegar al Punto de Encuentro'
                                      : 'Abrir en Google Maps / Otras apps',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Stack(
                              children: [
                                Container(
                                  height: 180,
                                  decoration: const BoxDecoration(
                                    image: DecorationImage(
                                      image: NetworkImage(
                                          'https://i.stack.imgur.com/vhoa0.jpg'), // Placeholder estilo mapa
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                        sigmaX: 4.0, sigmaY: 4.0),
                                    child: Container(
                                        color: Colors.black
                                            .withValues(alpha: 0.2)),
                                  ),
                                ),
                                Positioned.fill(
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 16),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.1),
                                              blurRadius: 10)
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.lock_rounded,
                                            color: Colors.grey[700],
                                            size: 32,
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'Ubicación exacta secreta',
                                            style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Franja que difumina el contenido bajo la acción flotante, para que
          // las tarjetas no se corten en seco detrás del botón.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 120 + MediaQuery.paddingOf(context).bottom,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context)
                          .scaffoldBackgroundColor
                          .withValues(alpha: 0),
                      Theme.of(context)
                          .scaffoldBackgroundColor
                          .withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Acción flotante: no tapa la interfaz con un panel adicional.
          Positioned(
            bottom: 12,
            left: 18,
            right: 18,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 4),
              child: _buildBottomActions(
                context,
                activity,
                isOrganizer,
                userRequestStatus ??
                    appState.getMyRequestStatus(widget.activityId),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context, Activity activity,
      bool isOrganizer, JoinRequestStatus? currentStatus) {
    // Plan terminado: la acción pasa a ser calificar o revivirlo en el mural.
    if (activity.hasEnded) {
      final isMember =
          isOrganizer || currentStatus == JoinRequestStatus.accepted;
      if (!isMember) {
        return const _ActionDock(
          colors: [Color(0xFF94A3B8), Color(0xFF64748B)],
          icon: Icons.event_busy_rounded,
          title: 'Este plan ya terminó',
          subtitle: 'Busca otro parecido en el inicio',
        );
      }
      final needsRating = !isOrganizer &&
          context.watch<AppState>().pendingRatingIds.contains(activity.id);
      if (needsRating) {
        return _ActionDock(
          colors: const [Color(0xFFFBBF24), Color(0xFFF59E0B)],
          icon: Icons.star_rounded,
          title: 'Califica el plan',
          subtitle: 'Tu nota cuenta para ${activity.organizerName.split(' ').first}',
          onPressed: () =>
              context.push('/main/activity/${activity.id}/feedback'),
        );
      }
      return _ActionDock(
        colors: const [Color(0xFFF472B6), Color(0xFFDB2777)],
        icon: Icons.photo_library_rounded,
        title: 'Mural de recuerdos',
        subtitle: activity.isChatOpen
            ? 'Sube tu foto · el chat cierra pronto'
            : 'Revive el plan con las fotos del grupo',
        onPressed: () => context.push('/main/activity/${activity.id}/photos'),
      );
    }

    if (isOrganizer) {
      return _ActionDock(
        colors: const [Color(0xFFFF9A4D), Color(0xFFEA4E00)],
        icon: Icons.shield_rounded,
        title: 'Administrar grupo',
        subtitle: 'Chat, aportes y solicitudes',
        onPressed: () => context.push('/main/activity/${activity.id}/group'),
      );
    }

    if (currentStatus == null) {
      final spots = activity.remainingSpots;
      return _ActionDock(
        colors: const [Color(0xFFFF9A4D), Color(0xFFEA4E00)],
        icon: Icons.person_add_alt_1_rounded,
        title: 'Solicitar unirme',
        subtitle: spots > 0
            ? '$spots ${spots == 1 ? 'cupo libre' : 'cupos libres'}'
            : 'Sin cupos por ahora',
        onPressed: () => _showJoinDialogPremium(context, activity),
      );
    } else if (currentStatus == JoinRequestStatus.pending) {
      return const _ActionDock(
        colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
        icon: Icons.hourglass_top_rounded,
        title: 'Solicitud enviada',
        subtitle: 'El organizador te responderá pronto',
      );
    } else if (currentStatus == JoinRequestStatus.accepted) {
      return _ActionDock(
        colors: const [Color(0xFF34D399), Color(0xFF059669)],
        icon: Icons.chat_bubble_rounded,
        title: 'Abrir chat del grupo',
        subtitle: 'Coordina con los participantes',
        onPressed: () => context.push('/main/activity/${activity.id}/group'),
      );
    }

    return const SizedBox.shrink();
  }

  void _showJoinDialogPremium(BuildContext context, Activity activity) {
    _buildJoinBottomSheet(context, activity);
  }

  void _buildJoinBottomSheet(BuildContext context, Activity activity) {
    final appState = context.read<AppState>();
    final msgCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color ??
          Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        bool isBtnPressed = false;
        String participationType = 'individual';
        String? selectedClanId;

        return StatefulBuilder(
          builder: (context, setSubState) {
            final clans = appState.userClans;
            if (clans.isNotEmpty && selectedClanId == null) {
              selectedClanId = clans.first.id;
            }

            Widget buildQuickTag(
                IconData icon, String label, String textToAppend) {
              return InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  final currentText = msgCtrl.text;
                  if (currentText.isEmpty) {
                    msgCtrl.text = '$textToAppend ';
                  } else if (currentText.endsWith(' ')) {
                    msgCtrl.text = '$currentText$textToAppend ';
                  } else {
                    msgCtrl.text = '$currentText $textToAppend ';
                  }
                  // Mover el cursor al final del campo
                  msgCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: msgCtrl.text.length),
                  );
                  setSubState(() {});
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color ??
                        Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primaryOrange.withValues(alpha: 0.16),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryOrange.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 15, color: AppColors.primaryOrange),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppColors.primaryOrange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.add_rounded,
                          size: 14, color: AppColors.primaryOrange),
                    ],
                  ),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
                left: 24,
                right: 24,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF2E323F)
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Cabecera Premium
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryOrange.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.rocket_launch_rounded,
                            color: AppColors.primaryOrange, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Preséntate',
                              style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onSurface),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Envía un mensaje a ${activity.organizerName}',
                              style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? const Color(0xFF94A3B8)
                                      : Colors.grey[500],
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified,
                                size: 12, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text(
                              'Organizador',
                              style: GoogleFonts.outfit(
                                  fontSize: 9.5,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Tarjeta Informativa de Tips
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.03)
                          : AppColors.navyBlue.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.05)
                            : AppColors.navyBlue.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.tips_and_updates_rounded,
                            color: Colors.amber, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Un buen mensaje aumenta tus posibilidades de ser aceptado en el plan.',
                            style: GoogleFonts.outfit(
                                fontSize: 12.5,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? const Color(0xFFE2E8F0)
                                    : Colors.grey[700],
                                fontWeight: FontWeight.w500,
                                height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (clans.isNotEmpty) ...[
                    Text(
                      '¿Cómo deseas inscribirte?',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setSubState(() {
                                participationType = 'individual';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: participationType == 'individual'
                                    ? AppColors.primaryOrange
                                        .withValues(alpha: 0.1)
                                    : (Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? const Color(0xFF1E222B)
                                        : Colors.grey[100]),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: participationType == 'individual'
                                      ? AppColors.primaryOrange
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.person_rounded,
                                    color: participationType == 'individual'
                                        ? AppColors.primaryOrange
                                        : Colors.grey,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Individual',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: participationType == 'individual'
                                          ? AppColors.primaryOrange
                                          : (Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.white
                                              : const Color(0xFF041249)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setSubState(() {
                                participationType = 'clan';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: participationType == 'clan'
                                    ? AppColors.primaryOrange
                                        .withValues(alpha: 0.1)
                                    : (Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? const Color(0xFF1E222B)
                                        : Colors.grey[100]),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: participationType == 'clan'
                                      ? AppColors.primaryOrange
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.groups_rounded,
                                    color: participationType == 'clan'
                                        ? AppColors.primaryOrange
                                        : Colors.grey,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Con mi Clan',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: participationType == 'clan'
                                          ? AppColors.primaryOrange
                                          : (Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.white
                                              : const Color(0xFF041249)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (participationType == 'clan') ...[
                      Text(
                        'Selecciona tu Clan:',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF1E222B)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedClanId,
                            isExpanded: true,
                            dropdownColor:
                                Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF161920)
                                    : Colors.white,
                            items: clans.map((clan) {
                              return DropdownMenuItem<String>(
                                value: clan.id,
                                child: Text(
                                  clan.name,
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setSubState(() {
                                  selectedClanId = val;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],

                  // Campo de Texto de Alta Gama
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF0A0D14)
                          : const Color(0xFFF8F9FD),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.08)
                            : AppColors.navyBlue.withValues(alpha: 0.08),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: msgCtrl,
                      maxLines: 4,
                      maxLength: 150,
                      onChanged: (_) => setSubState(() {}),
                      style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText:
                            '¡Hola! Me encantaría unirme a esta increíble actividad porque...',
                        hintStyle: GoogleFonts.outfit(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF64748B)
                                    : Colors.grey[400],
                            fontSize: 13.5),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        border: InputBorder.none,
                        counterStyle: GoogleFonts.outfit(
                            fontSize: 10,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF64748B)
                                    : Colors.grey[400],
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sugerencias Rápidas
                  Text(
                    'Sugerencias rápidas para añadir:',
                    style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF94A3B8)
                            : Colors.grey[500],
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      buildQuickTag(Icons.waving_hand_rounded, 'Saludo',
                          '¡Hola! Me encantaría unirme al plan.'),
                      buildQuickTag(Icons.lunch_dining_rounded, 'Aporte',
                          'Puedo llevar algo para compartir.'),
                      buildQuickTag(Icons.directions_car_rounded, 'Movilidad',
                          'Voy en auto y tengo espacio.'),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Botón CTA Animado con Sombra de Neón y Rebote
                  GestureDetector(
                    onTapDown: (_) => setSubState(() => isBtnPressed = true),
                    onTapUp: (_) => setSubState(() => isBtnPressed = false),
                    onTapCancel: () => setSubState(() => isBtnPressed = false),
                    child: AnimatedScale(
                      scale: isBtnPressed ? 0.96 : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.primaryOrange,
                              Color(0xFFFF8E53)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryOrange
                                  .withValues(alpha: 0.35),
                              blurRadius: 16,
                              spreadRadius: 1,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            context.pop(); // Cerrar BottomSheet

                            try {
                              final success = participationType == 'clan'
                                  ? await appState.submitClanJoinRequest(
                                      widget.activityId,
                                      selectedClanId!,
                                      msgCtrl.text,
                                    )
                                  : await appState.submitJoinRequest(
                                      widget.activityId,
                                      msgCtrl.text,
                                    );

                              if (success) {
                                setState(() {
                                  userRequestStatus = JoinRequestStatus.pending;
                                });

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(
                                              Icons.rocket_launch_rounded,
                                              color: Colors.white,
                                              size: 20),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              participationType == 'clan'
                                                  ? '¡Solicitudes del clan enviadas con éxito!'
                                                  : 'Solicitud enviada a ${activity.organizerName}',
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: const Color(0xFF2E7D32),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                      margin: const EdgeInsets.all(16),
                                    ),
                                  );
                                }
                              } else {
                                throw Exception(
                                    appState.error ?? 'Error desconocido');
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Error al enviar la solicitud: $e'),
                                      backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: Text(
                            participationType == 'clan'
                                ? 'Inscribir mi Clan'
                                : 'Enviar Solicitud',
                            style: GoogleFonts.outfit(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Color _getCategoryColor(String category) {
    return CategoryConstants.colors[category] ?? AppColors.primaryOrange;
  }

  IconData _getCategoryIcon(String category) {
    return CategoryConstants.icons[category] ?? Icons.category_rounded;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Google Maps del detalle. La clave se inyecta desde android/maps.properties.
// ─────────────────────────────────────────────────────────────────────────────
class _GoogleActivityMap extends StatelessWidget {
  final Activity activity;

  const _GoogleActivityMap({required this.activity});

  @override
  Widget build(BuildContext context) {
    final destination = google_maps.LatLng(
      activity.latitude!,
      activity.longitude!,
    );
    final hasMeetingPoint = activity.hasSeparateMeetingPoint &&
        activity.meetingLatitude != null &&
        activity.meetingLongitude != null;
    final meetingPoint = hasMeetingPoint
        ? google_maps.LatLng(
            activity.meetingLatitude!,
            activity.meetingLongitude!,
          )
        : null;
    final center = meetingPoint == null
        ? destination
        : google_maps.LatLng(
            (meetingPoint.latitude + destination.latitude) / 2,
            (meetingPoint.longitude + destination.longitude) / 2,
          );

    return google_maps.GoogleMap(
      initialCameraPosition: google_maps.CameraPosition(
        target: center,
        zoom: hasMeetingPoint ? 14 : 15,
      ),
      markers: {
        if (meetingPoint != null)
          google_maps.Marker(
            markerId: const google_maps.MarkerId('meeting-point'),
            position: meetingPoint,
            infoWindow: google_maps.InfoWindow(
              title: activity.meetingLocationName.isNotEmpty
                  ? activity.meetingLocationName
                  : 'Punto de encuentro',
            ),
            icon: google_maps.BitmapDescriptor.defaultMarkerWithHue(
              google_maps.BitmapDescriptor.hueOrange,
            ),
          ),
        google_maps.Marker(
          markerId: const google_maps.MarkerId('activity-location'),
          position: destination,
          infoWindow: google_maps.InfoWindow(
            title: activity.locationName.isNotEmpty
                ? activity.locationName
                : activity.location,
          ),
          icon: google_maps.BitmapDescriptor.defaultMarkerWithHue(
            hasMeetingPoint
                ? google_maps.BitmapDescriptor.hueAzure
                : google_maps.BitmapDescriptor.hueOrange,
          ),
        ),
      },
      polylines: {
        if (meetingPoint != null)
          google_maps.Polyline(
            polylineId: const google_maps.PolylineId('route-reference'),
            points: [meetingPoint, destination],
            width: 4,
            color: AppColors.primaryOrange,
          ),
      },
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      compassEnabled: false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fichas de estadísticas compactas y estáticas.
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _PremiumStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.25
                  : 0.12),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.12
                    : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.2),
                  color.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 9.5,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF94A3B8)
                        : Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Acción principal flotante del detalle.
///
/// Una pastilla de vidrio esmerilado con degradado, ícono en burbuja, título
/// con una línea de contexto y una flecha en círculo. Sustituye al botón
/// plano que latía sin parar: el pulso distraía y no decía nada nuevo.
/// Sin [onPressed] se muestra como estado (p. ej. solicitud pendiente).
class _ActionDock extends StatefulWidget {
  final List<Color> colors;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;

  const _ActionDock({
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onPressed,
  });

  @override
  State<_ActionDock> createState() => _ActionDockState();
}

class _ActionDockState extends State<_ActionDock> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onPressed != null;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final shadow = widget.colors.last;

    final content = Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Icon(widget.icon, color: Colors.white, size: 21),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (interactive) ...[
          const SizedBox(width: 10),
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_forward_rounded,
                color: widget.colors.last, size: 20),
          ),
        ],
      ],
    );

    final dock = ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.colors.first.withValues(alpha: 0.96),
                widget.colors.last.withValues(alpha: 0.96),
              ],
            ),
            // Filo de luz arriba: da volumen sin recurrir a sombras duras.
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: content,
        ),
      ),
    );

    return Semantics(
      button: interactive,
      label: '${widget.title}. ${widget.subtitle}',
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: interactive
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: Duration(milliseconds: reduceMotion ? 0 : 120),
          curve: Curves.easeOut,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: shadow.withValues(alpha: _pressed ? 0.22 : 0.34),
                  blurRadius: _pressed ? 12 : 24,
                  spreadRadius: -4,
                  offset: Offset(0, _pressed ? 4 : 10),
                ),
              ],
            ),
            child: dock,
          ),
        ),
      ),
    );
  }
}
