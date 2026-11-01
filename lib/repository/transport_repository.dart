import 'gtfs_repository.dart';
import '../data/departure_places.dart';
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
  'transport_transfers',
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
  Future<List<TransportStop>> findOriginStops(String origin) async {
    if (origin.trim().isEmpty) return [];
    final db = (await cloud()).firestore;
    final place = departureNamed(origin.trim());
    final queries = [
      db
          .collection('transport_stops')
          .where('name', isEqualTo: origin.trim())
          .limit(100)
          .get(),
      if (place != null)
        db
            .collection('transport_stops')
            .where('departurePlaceId', isEqualTo: place.id)
            .limit(100)
            .get(),
    ];
    final snapshots = await Future.wait(queries);
    final repo = GtfsRepository(db);
    final gtfs = <TransportStop>[];
    for (final feed in await repo.feeds()) {
      if (feed['activeVersionId'] == null) continue;
      // Explicit endpoint aliases choose candidate platforms; they never create transfer edges.
      final names = {
        origin.trim(),
        if (origin.trim() == '札幌駅') ...['札幌駅前', '札幌駅北口'],
      };
      for (final name in names) {
        final rows = await repo.findStops(feed, name);
        gtfs.addAll(rows.map((r) => TransportStop(r['id'] as String, r)));
      }
    }
    // Same names at distinct platforms remain separate candidates; only IDs deduplicate.
    return {
      for (final stop in gtfs) stop.id: stop,
      for (final snapshot in snapshots)
        for (final doc in snapshot.docs)
          doc.id: TransportStop(doc.id, doc.data()),
    }.values.toList();
  }

  Future<TransportData> load(List<String> stopIds) async {
    if (stopIds.isEmpty) return TransportData([], [], [], [], []);
    final db = (await cloud()).firestore;
    final stops = <TransportStop>[];
    final routeIds = <String>{};
    for (final id in stopIds.where((id) => !id.contains('~')).toSet()) {
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
    final gtfs = await GtfsRepository(db).load(stopIds);
    return TransportData(
      [...stops, ...gtfs.stops],
      [...routes, ...gtfs.routes],
      [...trips, ...gtfs.trips],
      [...services, ...gtfs.services],
      [...fares, ...gtfs.fares],
    );
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

final originTransportStopsProvider =
    FutureProvider.family<List<TransportStop>, String>(
      (ref, origin) =>
          ref.watch(transportRepositoryProvider).findOriginStops(origin),
    );
