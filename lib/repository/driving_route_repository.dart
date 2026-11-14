import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/experience.dart';
import '../model/transport.dart';
import '../service/cloud/cloud_services.dart';
import '../service/transport/transport_admin_api.dart';

final drivingRouteSearchProvider = Provider<Future<Json> Function(Json)>(
  (ref) => (query) async {
    final cloud = await ref.read(cloudServicesProvider.future);
    await cloud.writer();
    final result = await transportFunctions()
        .httpsCallable('searchDrivingRoute')
        .call(query);
    return Map<String, dynamic>.from(result.data as Map);
  },
);

Json drivingEndpoint(Experience spot) => {
  'name': spot.displayName,
  'address': spot.address,
  'latitude': spot.latitude,
  'longitude': spot.longitude,
};
String drivingRouteKey(Experience from, Experience to) =>
    jsonEncode({'from': drivingEndpoint(from), 'to': drivingEndpoint(to)});
final drivingRouteProvider = FutureProvider.family<Json, String>((ref, key) {
  final query = Map<String, dynamic>.from(jsonDecode(key) as Map);
  if (sameDrivingLocation(query['from'] as Map, query['to'] as Map)) {
    // No road journey is needed inside the same location. This is not a
    // measured walking duration; the itinerary adds no driving time here.
    return {
      'walkingOnly': true,
      'durationSeconds': 0,
      'distanceMeters': 0,
      'provider': 'same_location',
    };
  }
  return ref.watch(drivingRouteSearchProvider)(query);
});

bool sameDrivingLocation(Map from, Map to) {
  String address(Object? value) => (value as String? ?? '')
      .trim()
      .replaceAllMapped(
        RegExp(r'[０-９]'),
        (match) => String.fromCharCode(match[0]!.codeUnitAt(0) - 0xfee0),
      )
      .replaceAll(RegExp(r'[\s　]+'), '')
      .replaceAll(RegExp('[－−‐‑–—]'), '-');
  final a = address(from['address']), b = address(to['address']);
  if (a.isNotEmpty && a == b) return true;
  final lat1 = from['latitude'], lon1 = from['longitude'];
  final lat2 = to['latitude'], lon2 = to['longitude'];
  return lat1 is num &&
      lon1 is num &&
      lat2 is num &&
      lon2 is num &&
      lat1.isFinite &&
      lon1.isFinite &&
      lat2.isFinite &&
      lon2.isFinite &&
      lat1.abs() <= 90 &&
      lat2.abs() <= 90 &&
      lon1.abs() <= 180 &&
      lon2.abs() <= 180 &&
      (lat1 - lat2).abs() < 0.000001 &&
      (lon1 - lon2).abs() < 0.000001;
}

bool isWalkableDrivingLeg(Experience from, Experience to) =>
    sameDrivingLocation(drivingEndpoint(from), drivingEndpoint(to));

bool hasDrivingLocation(Experience place) {
  final lat = place.latitude, lon = place.longitude;
  return (lat != null &&
          lon != null &&
          lat.isFinite &&
          lon.isFinite &&
          lat.abs() <= 90 &&
          lon.abs() <= 180) ||
      place.address.trim().isNotEmpty;
}
