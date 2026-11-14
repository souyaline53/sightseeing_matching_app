import 'package:latlong2/latlong.dart';
import '../../../data/departure_places.dart';
import '../../../model/experience.dart';

class MapVisit {
  final int? number;
  final String? endpoint;
  final String label, address;
  final LatLng? point;
  const MapVisit(
    this.number,
    this.label,
    this.address,
    this.point, {
    this.endpoint,
  });
  String get badge => number?.toString() ?? endpoint!;
  String get description =>
      '${number == null ? '' : '$number. '}$label${address.isEmpty ? '' : '\n$address'}';
}

List<MapVisit> itineraryMapVisits(
  String origin,
  DeparturePlace? departure,
  List<Experience> stops, {
  String? destination,
  DeparturePlace? arrival,
}) => [
  MapVisit(
    null,
    '出発：$origin',
    departure?.address ?? '',
    departure?.point,
    endpoint: '出発',
  ),
  for (var i = 0; i < stops.length; i++)
    MapVisit(
      i + 1,
      stops[i].displayName,
      stops[i].address,
      validMapPoint(stops[i].latitude, stops[i].longitude),
    ),
  MapVisit(
    null,
    '到着：${destination ?? origin}',
    (destination == null || destination == origin ? departure : arrival)
            ?.address ??
        '',
    (destination == null || destination == origin ? departure : arrival)?.point,
    endpoint: '到着',
  ),
];

LatLng? validMapPoint(double? latitude, double? longitude) =>
    latitude != null &&
        longitude != null &&
        latitude.isFinite &&
        longitude.isFinite &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180
    ? LatLng(latitude, longitude)
    : null;

/// Never bridge a visit whose location is missing: that would imply a different route.
List<List<LatLng>> itineraryMapLegs(List<MapVisit> visits) => [
  for (var i = 0; i + 1 < visits.length; i++)
    if (visits[i].point != null &&
        visits[i + 1].point != null &&
        visits[i].point != visits[i + 1].point)
      [visits[i].point!, visits[i + 1].point!],
];

List<List<MapVisit>> groupMapVisits(List<MapVisit> visits) {
  final groups = <LatLng, List<MapVisit>>{};
  for (final visit in visits) {
    if (visit.point != null) {
      groups.putIfAbsent(visit.point!, () => []).add(visit);
    }
  }
  return groups.values.toList();
}

String mapVisitBadge(List<MapVisit> group) {
  final endpoints = group
      .where((visit) => visit.number == null)
      .map((visit) => visit.badge)
      .toSet();
  return [
    if (endpoints.contains('出発')) '出発',
    if (endpoints.contains('到着')) '到着',
    ...group.where((visit) => visit.number != null).map((visit) => visit.badge),
  ].join('・');
}
