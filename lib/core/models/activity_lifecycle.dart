import 'activity_model.dart';

/// En qué momento de su vida está un plan.
enum ActivityPhase {
  /// Aún no empieza (o empieza hoy y todavía no termina el día).
  upcoming,

  /// Terminó: ya no aparece en el inicio. El chat sigue abierto 2 días.
  ended,

  /// Pasaron los 2 días de gracia: el chat es de sólo lectura.
  chatClosed,
}

/// Las mismas reglas que `activity_ends_at` y `activity_chat_closes_at` del
/// servidor (migración 20261124160000): el plan termina al acabar el día,
/// en hora de Perú, en que termina el evento, y el chat se cierra 2 días
/// después.
///
/// Perú no tiene horario de verano (UTC−5 todo el año), así que basta con
/// desplazar la hora: no depende de la zona horaria del teléfono.
extension ActivityLifecycle on Activity {
  static const Duration _limaOffset = Duration(hours: -5);
  static const Duration chatGrace = Duration(days: 2);

  /// Fin del día (hora de Lima) en que termina el evento, en UTC.
  DateTime get endsAt {
    final end = eventDateTime
        .toUtc()
        .add(Duration(minutes: (durationMinutes ?? 0).clamp(0, 100000)));
    final lima = end.add(_limaOffset);
    final nextMidnightLima = DateTime.utc(lima.year, lima.month, lima.day + 1);
    return nextMidnightLima.subtract(_limaOffset);
  }

  DateTime get chatClosesAt => endsAt.add(chatGrace);

  ActivityPhase phaseAt(DateTime now) {
    final t = now.toUtc();
    if (t.isBefore(endsAt)) return ActivityPhase.upcoming;
    if (t.isBefore(chatClosesAt)) return ActivityPhase.ended;
    return ActivityPhase.chatClosed;
  }

  ActivityPhase get phase => phaseAt(DateTime.now());

  /// Ya no se muestra en el inicio.
  bool get hasEnded => phase != ActivityPhase.upcoming;

  bool get isChatOpen => phase != ActivityPhase.chatClosed;
}

/// "en 5 h", "en 2 días", "hoy a las 23:59"… para el aviso de cierre.
String describeTimeLeft(Duration left) {
  if (left.isNegative || left == Duration.zero) return 'ya';
  if (left.inMinutes < 60) return 'en ${left.inMinutes} min';
  if (left.inHours < 24) {
    final h = left.inHours;
    return 'en $h ${h == 1 ? 'hora' : 'horas'}';
  }
  final d = (left.inHours / 24).ceil();
  return 'en $d ${d == 1 ? 'día' : 'días'}';
}
