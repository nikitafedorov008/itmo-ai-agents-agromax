import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'adaptive.dart';

LatLng? mapPoint(dynamic value) =>
    value is Map && value['lat'] is num && value['lng'] is num
    ? LatLng((value['lat'] as num).toDouble(), (value['lng'] as num).toDouble())
    : null;

class FieldMap extends StatefulWidget {
  const FieldMap({
    super.key,
    required this.field,
    required this.observations,
    this.expanded = false,
    this.onExpand,
    this.onObservationTap,
  });
  final Map field;
  final List<dynamic> observations;
  final bool expanded;
  final VoidCallback? onExpand;
  final ValueChanged<Map>? onObservationTap;
  @override
  State<FieldMap> createState() => _FieldMapState();
}

class _FieldMapState extends State<FieldMap> {
  bool failed = false;
  bool satellite = true;
  bool satelliteUnavailable = false;
  @override
  Widget build(BuildContext context) {
    final requestedSatellite = satellite;
    final center = mapPoint(widget.field['center']);
    if (center == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('Координаты поля пока не указаны.'),
      );
    }
    final boundary = (widget.field['boundary'] as List? ?? [])
        .map(mapPoint)
        .whereType<LatLng>()
        .toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: widget.expanded ? null : 200,
        child: Stack(
          children: [
            FlutterMap(
              key: ValueKey(widget.field['id']),
              options: MapOptions(
                initialCenter: center,
                initialZoom: boundary.isEmpty ? 14 : 13,
                interactionOptions: InteractionOptions(
                  flags: widget.expanded
                      ? InteractiveFlag.all
                      : InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  key: ValueKey(satellite),
                  urlTemplate: satellite
                      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'app.agromax.mobile',
                  errorTileCallback: (_, _, _) {
                    if ((!failed || satellite) && mounted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && satellite == requestedSatellite) {
                          setState(() {
                            if (satellite) {
                              satellite = false;
                              satelliteUnavailable = true;
                            } else {
                              failed = true;
                            }
                          });
                        }
                      });
                    }
                  },
                ),
                if (boundary.length >= 3)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: boundary,
                        color: forest.withValues(alpha: .2),
                        borderColor: satellite ? celery : forest,
                        borderStrokeWidth: 3,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 36,
                      height: 36,
                      child: Container(
                        decoration: BoxDecoration(
                          color: forest,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: const Icon(
                          CupertinoIcons.leaf_arrow_circlepath,
                          color: celery,
                          size: 20,
                        ),
                      ),
                    ),
                    for (final o in widget.observations)
                      if (mapPoint(o['location']) != null)
                        Marker(
                          point: mapPoint(o['location'])!,
                          child: GestureDetector(
                            onTap: widget.onObservationTap == null
                                ? null
                                : () => widget.onObservationTap!(o),
                            child: const Icon(
                              CupertinoIcons.location_solid,
                              color: forest,
                              size: 32,
                            ),
                          ),
                        ),
                  ],
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        satellite
                            ? 'Source: Esri, Vantor, Earthstar Geographics, GIS User Community'
                            : '© OpenStreetMap contributors',
                        style: const TextStyle(fontSize: 10, color: forest),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 12,
              left: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ivory,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    boundary.isEmpty ? 'Поле отмечено точкой' : 'Контур поля',
                    style: const TextStyle(fontSize: 13, color: forest),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 52,
              left: 12,
              child: Container(
                color: ivory,
                child: CupertinoSlidingSegmentedControl<bool>(
                  groupValue: satellite,
                  children: const {
                    false: Text('Схема', style: TextStyle(fontSize: 12)),
                    true: Text('Спутник', style: TextStyle(fontSize: 12)),
                  },
                  onValueChanged: (value) {
                    if (value != null) {
                      setState(() {
                        satellite = value;
                        failed = false;
                        satelliteUnavailable = false;
                      });
                    }
                  },
                ),
              ),
            ),
            if (satelliteUnavailable && !failed)
              const Positioned(
                left: 12,
                right: 12,
                bottom: 4,
                child: Text(
                  'Спутник недоступен · показана схема OSM',
                  style: TextStyle(fontSize: 11, backgroundColor: ivory),
                ),
              ),
            if (failed)
              Positioned(
                left: 12,
                right: 12,
                bottom: 32,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  color: ivory,
                  child: const Text(
                    'Подложка недоступна. Контур и точки сохранены; нужна связь для карты.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
            if (widget.onExpand != null)
              Positioned(
                right: 8,
                bottom: 30,
                child: Container(
                  decoration: BoxDecoration(
                    color: ivory,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: NativeButton.icon(
                    onPressed: widget.onExpand,
                    icon: const Icon(CupertinoIcons.map, color: forest),
                    label: const Text('Карта поля'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
