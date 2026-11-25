import 'package:geolocator/geolocator.dart';

import '../models/activity_model.dart';

/// Distancia en km desde [position] hasta el lugar de [activity].
///
/// Es la única forma de calcularla en la app: la tarjeta del inicio la medía
/// en vivo con la ubicación del usuario y el detalle mostraba
/// `activity.distance`, un valor que llega en 0 cuando el plan no viene de
/// una búsqueda por cercanía. Así el mismo plan decía "199.6 km" en una
/// pantalla y "0.0 km" en la otra.
///
/// Devuelve null si no se puede saber (sin ubicación del usuario ni
/// coordenadas del plan), para que la interfaz no invente un 0.
double? activityDistanceKm(Activity activity, Position? position) {
  if (position != null &&
      activity.latitude != null &&
      activity.longitude != null) {
    return Geolocator.distanceBetween(position.latitude, position.longitude,
            activity.latitude!, activity.longitude!) /
        1000;
  }
  return activity.distance > 0 ? activity.distance : null;
}

/// "850 m", "4.2 km" o "120 km".
String formatDistanceKm(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  if (km >= 100) return '${km.round()} km';
  return '${km.toStringAsFixed(1)} km';
}
