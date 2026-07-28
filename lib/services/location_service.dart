import 'package:geolocator/geolocator.dart';

import '../core/supabase.dart';

/// Position de l'utilisateur — toujours facultative.
///
/// Elle sert uniquement à trier par distance : « le maçon le plus proche »
/// plutôt que « un maçon quelque part à Abidjan ». Rien ne dépend d'elle,
/// et la position exacte n'est jamais exposée — la recherche ne renvoie
/// qu'une distance en kilomètres.
class LocationService {
  /// Demande l'autorisation et relève la position.
  /// Rend `null` si l'utilisateur refuse ou si le GPS est coupé.
  static Future<({double lat, double lon})?> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final pos = await Geolocator.getCurrentPosition();
    return (lat: pos.latitude, lon: pos.longitude);
  }

  /// Écrit la position en base. `null` l'efface.
  static Future<void> save(double? lat, double? lon) async {
    await db.rpc('set_my_location', params: {'p_lat': lat, 'p_lon': lon});
  }

  static Future<({double lat, double lon})?> saved() async {
    try {
      final rows = await db.rpc('get_my_location');
      final list = rows as List;
      if (list.isEmpty) return null;
      final r = list.first as Map<String, dynamic>;
      final lat = (r['lat'] as num?)?.toDouble();
      final lon = (r['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;
      return (lat: lat, lon: lon);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() => save(null, null);
}
