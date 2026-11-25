import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:join_app/core/models/event_photo_model.dart';
import 'package:join_app/core/models/activity_model.dart';
import 'package:join_app/core/providers/app_state.dart';
import 'package:join_app/core/theme/app_colors.dart';
import 'package:join_app/core/widgets/user_avatar.dart';
import 'package:join_app/features/activity_games/data/activity_game_models.dart';
import 'package:join_app/features/activity_games/data/activity_game_repository.dart';

/// Pantalla de Galería/Mural de Fotos del Evento
class EventPhotoGalleryScreen extends StatefulWidget {
  final String activityId;

  const EventPhotoGalleryScreen({super.key, required this.activityId});

  @override
  State<EventPhotoGalleryScreen> createState() => _EventPhotoGalleryScreenState();
}

class _EventPhotoGalleryScreenState extends State<EventPhotoGalleryScreen> {
  List<EventPhoto> photos = [];
  bool isLoading = true;
  bool isAuthorized = false; // Solo organizador o participantes
  bool hasUploadedPhoto = false; // Límite de 1 foto por persona
  String? currentUserId;
  Activity? activity;

  /// Integrantes del plan, para mencionarlos en la cabecera del mural.
  /// Sólo los miembros pueden leerlos (RLS); para el resto queda vacío.
  List<ActivityMember> members = [];

  @override
  void initState() {
    super.initState();
    _loadRecapData();
  }

  Future<void> _loadRecapData() async {
    setState(() => isLoading = true);
    try {
      final appState = context.read<AppState>();
      currentUserId = appState.currentUser?.id;
      final activityRepo = appState.activityRepository;

      // 1. Obtener detalles de la actividad
      activity = await activityRepo.getActivityById(widget.activityId);

      if (currentUserId != null && activity != null) {
        // 2. Verificar si es organizador
        final isOrganizer = activity!.organizerId == currentUserId;

        // 3. Verificar si es participante aprobado
        final isParticipant = await activityRepo.isUserParticipant(
          activityId: widget.activityId,
          userId: currentUserId!,
        );

        isAuthorized = isOrganizer || isParticipant;

        // 4. Verificar si ya subió foto
        hasUploadedPhoto = await activityRepo.hasUserUploadedPhoto(
          activityId: widget.activityId,
          userId: currentUserId!,
        );
      }

      // 5. Cargar fotos reales
      photos = await activityRepo.getEventPhotos(widget.activityId);

      // 6. Quiénes estuvieron (menciones del mural).
      if (isAuthorized) {
        members = await ActivityGameRepository()
            .fetchMembers(widget.activityId)
            .catchError((_) => <ActivityMember>[]);
      }
    } catch (e) {
      debugPrint('Error en _loadRecapData: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _toggleLike(EventPhoto photo) async {
    if (currentUserId == null) return;
    HapticFeedback.lightImpact();

    final isLiked = photo.hasLikedByUser(currentUserId!);
    final activityRepo = context.read<AppState>().activityRepository;

    try {
      // Toggle en DB
      await activityRepo.toggleLikePhoto(
        photoId: photo.id,
        userId: currentUserId!,
        like: !isLiked,
      );

      // Recargar fotos localmente
      final updatedPhotos = await activityRepo.getEventPhotos(widget.activityId);
      if (!mounted) return;
      setState(() => photos = updatedPhotos);
    } catch (e) {
      debugPrint('Error al cambiar like: $e');
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    if (currentUserId == null) return;

    if (!isAuthorized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solo el organizador y participantes aprobados de la aventura pueden subir fotos. 🔒'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (hasUploadedPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ya has subido tu foto de recuerdo. (Límite: 1 foto por persona) 📸'),
          backgroundColor: Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final picker = ImagePicker();

    // Modal para origen de la foto
    final XFile? image = await showModalBottomSheet<XFile?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161920) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Añadir foto al Mural',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF041249),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Comparte tu mejor momento de la aventura. Límite de 1 foto por persona.',
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final navigator = Navigator.of(ctx);
                        final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
                        navigator.pop(file);
                      },
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: const Text('Cámara'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryOrange.withValues(alpha: isDark ? 0.15 : 0.1),
                        foregroundColor: AppColors.primaryOrange,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final navigator = Navigator.of(ctx);
                        final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                        navigator.pop(file);
                      },
                      icon: const Icon(Icons.photo_library_rounded),
                      label: const Text('Galería'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryOrange,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (image == null || !mounted) return;

    // Diálogo para pie de foto
    final captionController = TextEditingController();
    final bool? confirmUpload = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF161920) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Pie de foto',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF041249)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(image.path),
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: captionController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: '¿Qué tal estuvo la aventura? (opcional)...',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey[400], fontSize: 13),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E222B) : Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: isDark ? BorderSide.none : const BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.primaryOrange, width: 2),
                  ),
                ),
                maxLines: 2,
                maxLength: 150,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar', style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Subir', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmUpload != true || !mounted) return;

    // Se captura antes de los await: después la pantalla puede haberse cerrado.
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();

    setState(() => isLoading = true);
    try {
      await appState.activityRepository.uploadEventPhoto(
        activityId: widget.activityId,
        userId: currentUserId!,
        photoPath: image.path,
        caption: captionController.text.trim().isNotEmpty ? captionController.text.trim() : null,
      );

      // Recargar datos
      await _loadRecapData();

      messenger.showSnackBar(
        SnackBar(
          content: const Text('¡Foto añadida al mural con éxito! 🌟'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al subir foto: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0D14) : const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(
          activity?.title ?? 'Mural del Evento',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF041249)),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF161920) : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF041249),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadRecapData,
          ),
        ],
      ),
      floatingActionButton: isAuthorized && !hasUploadedPhoto && !isLoading
          ? FloatingActionButton.extended(
              onPressed: _pickAndUploadPhoto,
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.add_a_photo_rounded),
              label: Text('Subir Recuerdo', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ).animate().scale(delay: 500.ms, duration: 400.ms, curve: Curves.elasticOut)
          : null,
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryOrange),
            )
          : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (activity != null)
                        _MuralHeader(
                          activity: activity!,
                          members: members,
                          photoCount: photos.length,
                          isOwner: activity!.organizerId == currentUserId,
                        ),
                      if (photos.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.photo_library_outlined,
                                    size: 56,
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey[350]),
                                const SizedBox(height: 14),
                                Text(
                                  'Mural sin recuerdos aún',
                                  style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF041249)),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isAuthorized
                                      ? 'Sube la foto que mejor resuma tu experiencia. Quedará en este mural para todo el grupo.'
                                      : 'Sólo quienes estuvieron en el plan pueden ver y publicar recuerdos.',
                                  style: TextStyle(
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey[500],
                                      fontSize: 13,
                                      height: 1.5),
                                  textAlign: TextAlign.center,
                                ),
                                if (isAuthorized && !hasUploadedPhoto) ...[
                                  const SizedBox(height: 20),
                                  ElevatedButton.icon(
                                    onPressed: _pickAndUploadPhoto,
                                    icon: const Icon(Icons.add_a_photo_rounded),
                                    label: const Text('Subir mi recuerdo'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryOrange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 14),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      // Grid/Cards de fotos del mural
                      Column(
                        children: photos.asMap().entries.map((entry) {
                          final index = entry.key;
                          final photo = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: _PhotoCard(
                              photo: photo,
                              currentUserId: currentUserId,
                              onLike: () => _toggleLike(photo),
                            ).animate().fadeIn(duration: 400.ms, delay: (index * 80).ms).slideY(begin: 0.05, end: 0),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
    );
  }
}

/// Cabecera del mural: de quién es (el organizador) y quiénes estuvieron.
///
/// El mural pertenece al organizador; desde el perfil de cada participante
/// el recuerdo enlaza aquí, así que esta cabecera es la "mención" que une a
/// todo el grupo con el mural de quien creó el plan.
class _MuralHeader extends StatelessWidget {
  final Activity activity;
  final List<ActivityMember> members;
  final int photoCount;
  final bool isOwner;

  const _MuralHeader({
    required this.activity,
    required this.members,
    required this.photoCount,
    required this.isOwner,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? Colors.white : const Color(0xFF041249);
    final muted = isDark ? Colors.white60 : const Color(0xFF64748B);
    final others = members.where((m) => !m.isOrganizer).toList();
    final names = others.map((m) => m.name.split(' ').first).toList();
    final mention = names.isEmpty
        ? null
        : names.length <= 3
            ? 'Con ${names.join(', ')}'
            : 'Con ${names.take(3).join(', ')} y ${names.length - 3} más';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF2A1630), const Color(0xFF161920)]
              : [const Color(0xFFFFF1F7), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: const Color(0xFFEC4899).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                imageUrl: activity.organizerImageUrl,
                name: activity.organizerName,
                radius: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOwner
                          ? 'Tu mural de recuerdos'
                          : 'Mural de ${activity.organizerName}',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: text),
                    ),
                    Text(
                      '${activity.title} · $photoCount ${photoCount == 1 ? 'foto' : 'fotos'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(fontSize: 12.5, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (mention != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 24.0 + 18 * (others.take(4).length - 1),
                  height: 26,
                  child: Stack(
                    children: [
                      for (final (i, m) in others.take(4).indexed)
                        Positioned(
                          left: 18.0 * i,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF161920)
                                      : Colors.white,
                                  width: 2),
                            ),
                            child: UserAvatar(
                                imageUrl: m.imageUrl, name: m.name, radius: 11),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mention,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: muted),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Una foto por persona. Aparece también en el perfil de cada '
            'integrante, enlazada a este mural.',
            style: GoogleFonts.outfit(fontSize: 11.5, color: muted),
          ),
        ],
      ),
    );
  }
}

/// Widget para mostrar cada foto del mural con estilo polaroid premium
class _PhotoCard extends StatelessWidget {
  final EventPhoto photo;
  final String? currentUserId;
  final VoidCallback onLike;

  const _PhotoCard({
    required this.photo,
    required this.currentUserId,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLiked = currentUserId != null && photo.hasLikedByUser(currentUserId!);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161920) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.2) : const Color(0xFF041249).withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info del Usuario que subió (Header de la foto)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundImage: photo.userImageUrl.isNotEmpty
                      ? (photo.userImageUrl.startsWith('assets/')
                          ? AssetImage(photo.userImageUrl) as ImageProvider
                          : NetworkImage(photo.userImageUrl))
                      : const AssetImage('assets/images/avatars/avatar_1.png') as ImageProvider,
                  radius: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        photo.userName,
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : const Color(0xFF041249)),
                      ),
                      Text(
                        _formatTime(photo.uploadedAt),
                        style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                // Icono decorativo de cámara
                Icon(Icons.camera_alt_outlined, size: 14, color: isDark ? Colors.white24 : Colors.grey[300]),
              ],
            ),
          ),

          // Foto del Evento
          ClipRRect(
            child: AspectRatio(
              aspectRatio: 4 / 3, // Proporción fotográfica estándar
              child: photo.photoUrl.isNotEmpty
                  ? (photo.photoUrl.startsWith('assets/')
                      ? Image.asset(photo.photoUrl, fit: BoxFit.cover)
                      : Image.network(
                          photo.photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, _, __) => Container(
                            color: isDark ? const Color(0xFF1E222B) : const Color(0xFFFFF7F5),
                            child: const Icon(Icons.image, color: AppColors.primaryOrange, size: 40),
                          ),
                        ))
                  : Container(
                      color: isDark ? const Color(0xFF1E222B) : const Color(0xFFFFF7F5),
                      child: const Icon(Icons.image, color: AppColors.primaryOrange, size: 40),
                    ),
            ),
          ),

          // Pie de foto y Likes (Footer de la foto)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photo.caption != null && photo.caption!.isNotEmpty) ...[
                  Text(
                    photo.caption!,
                    style: TextStyle(fontSize: 13.5, color: isDark ? Colors.white70 : const Color(0xFF2D3748), height: 1.45),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Botón de Like con micro-animación al presionar
                    GestureDetector(
                      onTap: onLike,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isLiked
                              ? Colors.red.withValues(alpha: isDark ? 0.15 : 0.05)
                              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.05)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isLiked ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                              color: isLiked ? Colors.red : (isDark ? Colors.white38 : Colors.grey[500]),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${photo.likes}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isLiked ? Colors.red : (isDark ? Colors.white60 : Colors.grey[600]),
                                fontWeight: isLiked ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Indicador de recuerdo único
                    Text(
                      'Recuerdo único ✨',
                      style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: isDark ? Colors.white24 : Colors.grey[400]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Ahora mismo';
    } else if (difference.inMinutes < 60) {
      return 'Hace ${difference.inMinutes} m';
    } else if (difference.inHours < 24) {
      return 'Hace ${difference.inHours} h';
    } else {
      return 'Hace ${difference.inDays} d';
    }
  }
}
