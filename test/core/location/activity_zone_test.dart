import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:join_app/core/location/activity_zone.dart';
import 'package:join_app/core/models/activity_model.dart';

Position pos(double lat, double lon) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime(2026),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Activity activity({
  String organizer = 'otro',
  String? city,
  double? lat,
  double? lon,
}) =>
    Activity(
      id: 'a',
      title: 'Plan',
      description: '',
      category: 'Deportes, Fútbol',
      maxParticipants: 10,
      organizerId: organizer,
      organizerName: 'Otro',
      eventDateTime: DateTime(2026, 12, 1),
      city: city,
      latitude: lat,
      longitude: lon,
    );

// Coordenadas reales de la base local.
final elTambo = pos(-12.0560, -75.2140);
const huancayoLat = -12.0512, huancayoLon = -75.2055; // "Partido Dominguero"
const limaLat = -12.0615, limaLon = -77.0471; // "Pichanga"

void main() {
  group('isActivityInUserZone', () {
    test('las propias siempre se ven', () {
      expect(
        isActivityInUserZone(activity(organizer: 'yo', lat: limaLat, lon: limaLon),
            userId: 'yo', userCity: 'El Tambo, Junín', userPosition: elTambo),
        isTrue,
      );
    });

    test('sin ciudad pero cerca por coordenadas: se ve (antes se descartaba)', () {
      expect(
        isActivityInUserZone(activity(lat: huancayoLat, lon: huancayoLon),
            userId: 'yo', userCity: 'El Tambo, Junín', userPosition: elTambo),
        isTrue,
      );
    });

    test('sin ciudad y lejos por coordenadas: no se ve', () {
      expect(
        isActivityInUserZone(activity(lat: limaLat, lon: limaLon),
            userId: 'yo', userCity: 'El Tambo, Junín', userPosition: elTambo),
        isFalse,
      );
    });

    test('sin ciudad y sin posición del usuario: se muestra, como en el servidor', () {
      expect(
        isActivityInUserZone(activity(lat: limaLat, lon: limaLon),
            userId: 'yo', userCity: 'El Tambo, Junín', userPosition: null),
        isTrue,
      );
    });

    test('con ciudad de la misma zona: se ve aunque no haya posición', () {
      expect(
        isActivityInUserZone(activity(city: 'Huancayo, Junín'),
            userId: 'yo', userCity: 'El Tambo, Junín', userPosition: null),
        isTrue,
      );
    });

    test('ciudad escrita distinto pero cerca de verdad: se ve', () {
      expect(
        isActivityInUserZone(
            activity(city: 'Ciudad Universitaria', lat: huancayoLat, lon: huancayoLon),
            userId: 'yo', userCity: 'El Tambo, Junín', userPosition: elTambo),
        isTrue,
      );
    });

    test('con ciudad de otra región y lejos: no se ve', () {
      expect(
        isActivityInUserZone(
            activity(city: 'Miraflores, Lima', lat: limaLat, lon: limaLon),
            userId: 'yo', userCity: 'El Tambo, Junín', userPosition: elTambo),
        isFalse,
      );
    });

    test('con radio de búsqueda manda la distancia real', () {
      final cerca = activity(lat: huancayoLat, lon: huancayoLon);
      expect(
        isActivityInUserZone(cerca,
            userId: 'yo', userCity: 'El Tambo, Junín', userPosition: elTambo, radiusKm: 5),
        isTrue,
      );
      expect(
        isActivityInUserZone(activity(lat: limaLat, lon: limaLon),
            userId: 'yo', userCity: 'El Tambo, Junín', userPosition: elTambo, radiusKm: 100),
        isFalse,
      );
    });

    test('usuario sin ciudad ni posición ve todo', () {
      expect(
        isActivityInUserZone(activity(city: 'Miraflores, Lima'),
            userId: 'yo', userCity: null, userPosition: null),
        isTrue,
      );
    });
  });
}
