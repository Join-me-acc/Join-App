import 'package:flutter_test/flutter_test.dart';
import 'package:join_app/core/models/activity_lifecycle.dart';
import 'package:join_app/core/models/activity_model.dart';

Activity at(DateTime utc, {int? minutes = 120}) => Activity(
      id: 'a',
      title: 'Plan',
      description: '',
      category: 'Deportes',
      maxParticipants: 10,
      organizerName: 'Orga',
      eventDateTime: utc,
      durationMinutes: minutes,
    );

void main() {
  group('ActivityLifecycle', () {
    test('coincide con el servidor: 19 jun 08:00 UTC termina el 20 a las 05:00 UTC', () {
      // Valores sacados de activity_ends_at() en la base local.
      final a = at(DateTime.utc(2026, 6, 19, 8));
      expect(a.endsAt, DateTime.utc(2026, 6, 20, 5));
      expect(a.chatClosesAt, DateTime.utc(2026, 6, 22, 5));
    });

    test('un evento de noche en Lima que pasa la medianoche UTC sigue siendo de ese día', () {
      // 24 nov 20:00 UTC = 15:00 en Lima → termina al acabar el 24 en Lima.
      final a = at(DateTime.utc(2026, 11, 24, 20));
      expect(a.endsAt, DateTime.utc(2026, 11, 25, 5));
    });

    test('la duración que cruza la medianoche de Lima mueve el fin al día siguiente', () {
      // 23:00 en Lima (04:00 UTC del 25) + 2 h = 01:00 del 25 en Lima.
      final a = at(DateTime.utc(2026, 11, 25, 4));
      expect(a.endsAt, DateTime.utc(2026, 11, 26, 5));
    });

    test('fases', () {
      final a = at(DateTime.utc(2026, 6, 19, 8));
      expect(a.phaseAt(DateTime.utc(2026, 6, 19, 23)), ActivityPhase.upcoming);
      expect(a.phaseAt(DateTime.utc(2026, 6, 20, 5)), ActivityPhase.ended);
      expect(a.phaseAt(DateTime.utc(2026, 6, 22, 4, 59)), ActivityPhase.ended);
      expect(a.phaseAt(DateTime.utc(2026, 6, 22, 5)), ActivityPhase.chatClosed);
    });

    test('sin duración usa sólo la hora de inicio', () {
      expect(at(DateTime.utc(2026, 6, 19, 8), minutes: null).endsAt,
          DateTime.utc(2026, 6, 20, 5));
    });
  });

  test('describeTimeLeft', () {
    expect(describeTimeLeft(const Duration(minutes: 30)), 'en 30 min');
    expect(describeTimeLeft(const Duration(hours: 1, minutes: 5)), 'en 1 hora');
    expect(describeTimeLeft(const Duration(hours: 20)), 'en 20 horas');
    expect(describeTimeLeft(const Duration(hours: 30)), 'en 2 días');
    expect(describeTimeLeft(Duration.zero), 'ya');
  });
}
