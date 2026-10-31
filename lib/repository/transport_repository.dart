import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/transport.dart';
import '../service/cloud/cloud_services.dart';

const transportCollections = [
  'transport_agencies',
  'transport_stops',
  'transport_routes',
  'transport_services',
  'transport_trips',
  'transport_fares',
];

class TransportData {
  final List<TransportStop> stops;
  final List<TransportRoute> routes;
  final List<TransportTrip> trips;
  final List<TransportService> services;
  final List<TransportFare> fares;
  TransportData(this.stops, this.routes, this.trips, this.services, this.fares);
  String stopName(String id) =>
      stops.where((s) => s.id == id).firstOrNull?.name ?? id;
}

class TransportRepository {
  final Future<CloudServices> Function() cloud;
  TransportRepository(this.cloud);
  Future<TransportData> load(List<String> stopIds) async {
    if (stopIds.isEmpty) return TransportData([], [], [], [], []);
    final db = (await cloud()).firestore;
    final stops = <TransportStop>[];
    final routeIds = <String>{};
    for (final id in stopIds.toSet()) {
      final doc = await db.collection('transport_stops').doc(id).get();
      if (doc.exists) {
        stops.add(TransportStop(doc.id, doc.data()!));
        routeIds.addAll(
          (doc.data()!['routeIds'] as List? ?? []).cast<String>(),
        );
      }
    }
    final routes = <TransportRoute>[];
    final trips = <TransportTrip>[];
    final fares = <TransportFare>[];
    // Route pagination avoids truncating the available timetable or reading unrelated regions.
    for (final id in routeIds) {
      final route = await db.collection('transport_routes').doc(id).get();
      if (!route.exists) continue;
      routes.add(TransportRoute(id, route.data()!));
      for (final collection in ['transport_trips', 'transport_fares']) {
        DocumentSnapshot<Map<String, dynamic>>? cursor;
        while (true) {
          Query<Map<String, dynamic>> q = db
              .collection(collection)
              .where('routeId', isEqualTo: id)
              .orderBy(FieldPath.documentId)
              .limit(100);
          if (cursor != null) q = q.startAfterDocument(cursor);
          final page = await q.get();
          for (final d in page.docs) {
            if (collection == 'transport_trips') {
              trips.add(TransportTrip(d.id, d.data()));
            } else {
              fares.add(TransportFare(d.id, d.data()));
            }
          }
          if (page.docs.length < 100) break;
          cursor = page.docs.last;
        }
      }
    }
    final services = <TransportService>[];
    for (final id in trips.map((t) => t.data['serviceId'] as String).toSet()) {
      final doc = await db.collection('transport_services').doc(id).get();
      if (doc.exists) services.add(TransportService(id, doc.data()!));
    }
    for (final id
        in trips
            .expand((t) => t.times.map((s) => s.stopId))
            .toSet()
            .difference(stops.map((s) => s.id).toSet())) {
      final doc = await db.collection('transport_stops').doc(id).get();
      if (doc.exists) stops.add(TransportStop(id, doc.data()!));
    }
    return TransportData(stops, routes, trips, services, fares);
  }
}

final transportRepositoryProvider = Provider(
  (ref) => TransportRepository(() => ref.read(cloudServicesProvider.future)),
);
// JSON key gives family providers stable equality across rebuilds and caches per stop set.
final transportDataProvider = FutureProvider.family<TransportData, String>(
  (ref, key) => ref
      .watch(transportRepositoryProvider)
      .load((jsonDecode(key) as List).cast<String>()),
);
