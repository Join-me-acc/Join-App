import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lo que pasa cuando un plan termina: calificaciones y el barrido que lo
/// marca como terminado y avisa a los integrantes.
///
/// Las reglas (quién puede calificar, cuándo se cierra el chat) viven en el
/// servidor: ver la migración 20261124160000_activity_lifecycle.sql.
class ActivityLifecycleRepository {
  final SupabaseClient _supabase;

  ActivityLifecycleRepository({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  String? get _userId => _supabase.auth.currentUser?.id;

  /// Marca los planes terminados y envía los avisos pendientes. Lo programa
  /// pg_cron cada 10 min; la app también lo llama al abrirse por si en ese
  /// entorno no hay cron. Es idempotente.
  Future<void> sweep() async {
    try {
      await _supabase.rpc('sweep_activity_lifecycle');
    } catch (e) {
      debugPrint('Barrido del ciclo de vida no disponible: $e');
    }
  }

  /// IDs de los planes terminados que el usuario aún debe calificar.
  Future<Set<String>> pendingRatingIds() async {
    try {
      final rows = await _supabase.rpc('my_pending_ratings');
      return {
        for (final r in (rows as List? ?? const []))
          (r as Map<String, dynamic>)['activity_id'] as String,
      };
    } catch (e) {
      debugPrint('Error en my_pending_ratings: $e');
      return {};
    }
  }

  Future<bool> hasRated(String activityId) async {
    final userId = _userId;
    if (userId == null) return false;
    final row = await _supabase
        .from('event_feedback')
        .select('id')
        .eq('activity_id', activityId)
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  Future<void> submitFeedback({
    required String activityId,
    required int groupRating,
    required int attendanceScore,
    required bool wouldAttendAgain,
    String comment = '',
    List<String> bestThings = const [],
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('No hay sesión activa.');

    final inserted = await _supabase
        .from('event_feedback')
        .insert({
          'activity_id': activityId,
          'user_id': userId,
          'group_rating': groupRating,
          'attendance_score': attendanceScore,
          'would_attend_again': wouldAttendAgain,
          if (comment.trim().isNotEmpty) 'group_comment': comment.trim(),
        })
        .select('id')
        .single();

    if (bestThings.isNotEmpty) {
      await _supabase.from('event_feedback_tags').insert([
        for (final tag in bestThings)
          {'feedback_id': inserted['id'], 'type': 'best', 'tag': tag},
      ]);
    }
  }
}
