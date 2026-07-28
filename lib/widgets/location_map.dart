import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';

/// Aperçu cartographique de la position, avec repositionnement au doigt.
///
/// Fonds de carte OpenStreetMap : libres, sans clé d'API ni facturation.
/// Le GPS est imprécis dans les quartiers denses, d'où la possibilité de
/// corriger le point en touchant la carte — c'est souvent plus juste que
/// ce que renvoie le téléphone.
class LocationMap extends StatelessWidget {
  final double lat;
  final double lon;
  final ValueChanged<({double lat, double lon})>? onMoved;
  final double height;

  const LocationMap({
    super.key,
    required this.lat,
    required this.lon,
    this.onMoved,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lon);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 15,
            onTap: onMoved == null
                ? null
                : (_, p) => onMoved!((lat: p.latitude, lon: p.longitude)),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'app.ticonnect',
            ),
            MarkerLayer(markers: [
              Marker(
                point: point,
                width: 44,
                height: 44,
                child: const Icon(Icons.location_on,
                    size: 44, color: AppTheme.danger),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
