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
final drivingRouteProvider = FutureProvider.family<Json, String>(
  (ref, key) => ref.watch(drivingRouteSearchProvider)(
    Map<String, dynamic>.from(jsonDecode(key) as Map),
  ),
);

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
