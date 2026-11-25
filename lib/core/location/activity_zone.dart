import 'package:geolocator/geolocator.dart';

import '../models/activity_model.dart';
import 'peru_geography.dart';

/// Radio con el que se considera "de tu zona" una actividad que no tiene
/// ciudad guardada pero sí coordenadas. Cubre una provincia y sus vecinas
/// (El Tambo–Jauja son ~40 km) sin traer planes de otra región.
const double kZoneFallbackRadiusKm = 60;

/// ¿Debe ver [userId] la actividad [a] en su inicio?
///
/// Reglas, en orden:
///  1. Las propias siempre se ven.
///  2. Con radio de búsqueda ([radiusKm] > 0) y coordenadas de ambos lados,
///     manda la distancia real.
///  3. Si la actividad tiene ciudad, se compara con la del usuario como
///     siempre ([PeruGeography.proximityScore]).
///  4. Si no tiene ciudad pero sí coordenadas y se conoce la posición del
///     usuario, se usa la distancia con [kZoneFallbackRadiusKm].
///  5. Si no hay forma de saberlo, se muestra: es lo mismo que hace la
///     función `activities_near` del servidor, que no descarta las que no
///     tienen ciudad.
///
/// Antes faltaban los pasos 4 y 5: las actividades sin ciudad (todas las
/// creadas desde la app, porque el formulario no la rellenaba) recibían
/// puntuación 100 y se descartaban, así que cada usuario sólo veía sus
/// propios planes.
bool isActivityInUserZone(
  Activity a, {
  required String? userId,
  required String? userCity,
  required Position? userPosition,
  double radiusKm = 0,
}) {
  if (userId != null && a.organizerId == userId) return true;
  // Sin ninguna referencia del usuario no hay con qué filtrar.
  if ((userCity ?? '').trim().isEmpty && userPosition == null) return true;

  final hasCoords = a.latitude != null && a.longitude != null;
  final distanceKm = hasCoords && userPosition != null
      ? Geolocator.distanceBetween(userPosition.latitude,
              userPosition.longitude, a.latitude!, a.longitude!) /
          1000
      : null;

  if (radiusKm > 0 && distanceKm != null) return distanceKm <= radiusKm;

  final activityCity = a.city?.trim() ?? '';
  if (activityCity.isNotEmpty) {
    if (PeruGeography.proximityScore(userCity ?? '', activityCity) < 100) {
      return true;
    }
    // La ciudad escrita puede no coincidir con el formato de la del usuario
    // ("Huancayo" frente a "El Tambo, Junín"): si está cerca de verdad, vale.
    return distanceKm != null && distanceKm <= kZoneFallbackRadiusKm;
  }

  if (distanceKm != null) return distanceKm <= kZoneFallbackRadiusKm;
  return true;
}
