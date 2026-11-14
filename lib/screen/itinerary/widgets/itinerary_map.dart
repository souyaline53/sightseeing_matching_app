import '../../../theme/app_theme.dart';
import 'dart:math' as math;
import 'itinerary_map_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/departure_places.dart';
import '../../../widgets/departure_map.dart' show mapTilesEnabledProvider;

import 'package:latlong2/latlong.dart' show LatLng;
import '../../../state/trip_state.dart';
import '../../../data/catalog_data.dart';

class ItineraryMap extends ConsumerStatefulWidget {
  final String origin;
  final String? destination;
  final double bottomInset;
  const ItineraryMap({
    super.key,
    required this.origin,
    this.destination,
    this.bottomInset = 0,
  });
  @override
  ConsumerState<ItineraryMap> createState() => _MapState();
}

class _MapState extends ConsumerState<ItineraryMap> {
  bool failed = false;
  final map = MapController();
  bool ready = false;
  String? fitted;
  String? scheduled;

  @override
  void dispose() {
    map.dispose();
    super.dispose();
  }

  void fitVisits(
    List<LatLng> points,
    Size size,
    double markerWidth,
    String locations,
  ) {
    final inset = widget.bottomInset;
    final visibleHeight = size.height - inset;
    if (points.isEmpty || visibleHeight < 100 || size.width < 100) {
      scheduled = null;
      return;
    }
    // Visit order and badge width can change on reorder without changing locations.
    final signature = '$locations:$size:$inset';
    if (fitted == signature || scheduled == signature) return;
    scheduled = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || scheduled != signature) return;
      scheduled = null;
      if (!ready || widget.bottomInset != inset) return;
      map.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          // The inner 80% of the unobscured viewport, plus room for the pin itself.
          padding: EdgeInsets.fromLTRB(
            size.width * .1 + markerWidth / 2,
            visibleHeight * .1 + 52,
            size.width * .1 + markerWidth / 2,
            inset + visibleHeight * .1 + 24,
          ),
          maxZoom: 14,
        ),
      );
      fitted = signature;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(mapTilesEnabledProvider);
    final catalog = ref.watch(catalogProvider).value?.experiences ?? [];
    final stops = ref
        .watch(tripProvider)
        .stops
        .map(
          (stop) => catalog.where((e) => e.id == stop.id).firstOrNull ?? stop,
        )
        .toList();
    final departure = departureNamed(
      widget.origin,
      ref.watch(departurePlacesProvider).value ?? [],
    );
    final visits = itineraryMapVisits(
      widget.origin,
      departure,
      stops,
      destination: widget.destination,
      arrival: departureNamed(
        widget.destination ?? widget.origin,
        ref.watch(departurePlacesProvider).value ?? [],
      ),
    );
    final groups = groupMapVisits(visits);
    final points = groups.map((g) => g.first.point!).toList();
    final legs = itineraryMapLegs(visits);
    final locations =
        (groups.map((group) => '${group.first.point}:${group.length}').toList()
              ..sort())
            .join(';');
    final markerWidth = groups.fold<double>(
      48,
      (width, group) => math.max(width, _pinWidth(group)),
    );
    final color = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        fitVisits(points, size, markerWidth, locations);
        return Stack(
          fit: StackFit.expand,
          children: [
            FlutterMap(
              mapController: map,
              options: MapOptions(
                onMapReady: () {
                  ready = true;
                  fitVisits(points, size, markerWidth, locations);
                },
                initialCenter:
                    points.firstOrNull ?? const LatLng(43.0687, 141.3508),
                initialZoom: 12,
                minZoom: 0,
                maxZoom: 18,
                backgroundColor: AppColors.softSurface,
              ),
              children: [
                if (enabled)
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'jp.tabisaki.prototype',
                    maxNativeZoom: 19,
                    errorTileCallback: (_, error, stack) {
                      if (!failed) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && !failed) setState(() => failed = true);
                        });
                      }
                    },
                  ),
                if (legs.isNotEmpty) ...[
                  PolylineLayer(
                    polylines: [
                      for (final leg in legs)
                        Polyline(
                          points: leg,
                          strokeWidth: 3,
                          color: color,
                          pattern: const StrokePattern.dotted(
                            spacingFactor: 2.5,
                          ),
                        ),
                    ],
                  ),
                  _DirectionArrows(legs: legs, color: color),
                ],
                if (groups.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      for (final group in groups)
                        Marker(
                          key: ValueKey(
                            '${group.first.point}:${mapVisitBadge(group)}',
                          ),
                          point: group.first.point!,
                          width: _pinWidth(group),
                          height: 52,
                          alignment: Alignment.topCenter,
                          rotate: true,
                          child: Tooltip(
                            message: group.map((v) => v.description).join('\n'),
                            child: Semantics(
                              label: group.map((v) => v.description).join('、'),
                              child: Column(
                                children: [
                                  Container(
                                    height: 34,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          mapVisitBadge(group),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    size: 18,
                                    color: color,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            // At the top so attribution remains visible when the sheet covers the map.
            Positioned(
              top: 4,
              left: 8,
              child: Material(
                color: Colors.white.withValues(alpha: .9),
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  onTap: () => launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(fontSize: 9),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: '旅程全体を表示',
                onPressed: points.isEmpty
                    ? null
                    : () => setState(() => fitted = null),
                icon: const Icon(Icons.fit_screen),
              ),
            ),
            if (visits.any((v) => v.point == null))
              Positioned(
                left: 12,
                right: 64,
                bottom: widget.bottomInset + 8,
                child: IgnorePointer(
                  child: Text(
                    '位置未設定：${visits.where((v) => v.point == null).map((v) => v.badge).join('・')}',
                    style: const TextStyle(
                      fontSize: 11,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            if (failed || !enabled)
              const Positioned(
                top: 30,
                left: 12,
                child: Text(
                  '地図を読み込めません。旅程の編集は続けられます。',
                  style: TextStyle(fontSize: 10, backgroundColor: Colors.white),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Uses screen coordinates so arrowheads follow the straight lines even when rotated.
class _DirectionArrows extends StatelessWidget {
  final List<List<LatLng>> legs;
  final Color color;
  const _DirectionArrows({required this.legs, required this.color});
  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ArrowPainter([
          for (final leg in legs)
            [
              camera.latLngToScreenOffset(leg[0]),
              camera.latLngToScreenOffset(leg[1]),
            ],
        ], color),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final List<List<Offset>> legs;
  final Color color;
  _ArrowPainter(this.legs, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final leg in legs) {
      final delta = leg[1] - leg[0];
      if (delta.distance < 1) continue;
      // Opposite legs have their arrows at different positions on the shared line.
      final tip = leg[0] + delta * .65;
      final angle = math.atan2(delta.dy, delta.dx);
      final backward =
          Offset(math.cos(angle), math.sin(angle)) *
          math.min(11, delta.distance * .2);
      final side =
          Offset(-math.sin(angle), math.cos(angle)) *
          math.min(6, delta.distance * .1);
      canvas.drawPath(
        Path()
          ..moveTo((tip - backward + side).dx, (tip - backward + side).dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo((tip - backward - side).dx, (tip - backward - side).dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) => true;
}

double _pinWidth(List<MapVisit> group) =>
    (mapVisitBadge(group).runes.fold<double>(
              0,
              (width, rune) => width + (rune > 255 ? 17 : 11),
            ) +
            24)
        .clamp(48, 200);
