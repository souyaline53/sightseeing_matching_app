import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/transport.dart';
import 'transport_repository.dart';

/// Immutable versions make cached pages safe; active pointers are refreshed per request.
class GtfsRepository {
  final FirebaseFirestore db;
  GtfsRepository(this.db);
  static final _cache = <String, List<Json>>{};
  static final _sizes = <String, int>{};
  static int _bytes = 0;
  static int fetchedDocuments = 0, fetchRequests = 0;
  static void clearCache() {
    _cache.clear();
    _sizes.clear();
    _bytes = 0;
  }

  static List<Json> remember(String key, List<Json> rows) {
    final size = utf8
        .encode(jsonEncode(rows, toEncodable: (v) => v.toString()))
        .length;
    if (size > 8 * 1024 * 1024) return rows;
    _bytes -= _sizes.remove(key) ?? 0;
    _cache.remove(key);
    while (_cache.isNotEmpty &&
        (_bytes + size > 8 * 1024 * 1024 || _cache.length >= 128)) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _bytes -= _sizes.remove(oldest) ?? 0;
    }
    _cache[key] = rows;
    _sizes[key] = size;
    _bytes += size;
    return rows;
  }

  Future<List<Json>> feeds() async {
    final result = <Json>[];
    DocumentSnapshot<Json>? cursor;
    while (true) {
      Query<Json> q = db
          .collection('transport_feeds')
          .orderBy(FieldPath.documentId)
          .limit(100);
      if (cursor != null) q = q.startAfterDocument(cursor);
      final page = await q.get();
      fetchRequests++;
      fetchedDocuments += page.docs.length;
      result.addAll(page.docs.map((d) => {...d.data(), 'id': d.id}));
      if (page.docs.length < 100) break;
      cursor = page.docs.last;
    }
    return result;
  }

  CollectionReference<Json> collection(Json feed, String name) => db
      .collection('transport_feeds')
      .doc(feed['id'] as String)
      .collection('versions')
      .doc(feed['activeVersionId'] as String)
      .collection(name);
  Future<List<Json>> page(
    CollectionReference<Json> c, {
    String? field,
    Object? value,
    String? after,
    bool array = false,
  }) async {
    final cacheKey = '${db.app.name}/${c.path}/$field/$value/$after/$array';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;
    Query<Json> q = c;
    if (field != null) {
      q = array
          ? q.where(field, arrayContains: value)
          : q.where(field, isEqualTo: value);
    }
    q = q.orderBy(FieldPath.documentId).limit(100);
    if (after != null) q = q.startAfter([after]);
    final docs = await q.get();
    fetchRequests++;
    fetchedDocuments += docs.docs.length;
    return remember(
      cacheKey,
      docs.docs.map((d) => {...d.data(), 'id': d.id}).toList(),
    );
  }

  Future<List<Json>> all(
    CollectionReference<Json> c, {
    String? field,
    Object? value,
    bool array = false,
  }) async {
    final out = <Json>[];
    String? cursor;
    do {
      final rows = await page(
        c,
        field: field,
        value: value,
        array: array,
        after: cursor,
      );
      out.addAll(rows);
      if (rows.length < 100) break;
      cursor = rows.last['id'] as String;
    } while (true);
    return out;
  }

  Future<Json?> record(CollectionReference<Json> c, String id) async {
    final k = '${db.app.name}/${c.path}/$id';
    if (_cache.containsKey(k)) return _cache[k]!.firstOrNull;
    final d = await c.doc(id).get();
    fetchRequests++;
    fetchedDocuments += d.exists ? 1 : 0;
    final value = d.data();
    remember(k, value == null ? [] : [value]);
    return value;
  }

  Future<TransportData> load(List<String> ids) async {
    final stops = <String, TransportStop>{},
        routes = <String, TransportRoute>{},
        trips = <String, TransportTrip>{},
        services = <String, TransportService>{},
        fares = <String, TransportFare>{};
    for (final feed in await feeds()) {
      if (feed['activeVersionId'] == null) continue;
      final prefix = '${feed['id']}~';
      final selected = ids.where((id) => id.startsWith(prefix)).toSet();
      if (selected.isEmpty) continue;
      for (final id in selected) {
        for (final r in await all(
          collection(feed, 'transport_trips'),
          field: 'stopIds',
          value: id,
          array: true,
        )) {
          trips[r['id'] as String] = TransportTrip(r['id'] as String, r);
        }
      }
      final feedTrips = trips.values
          .where((t) => t.data['feedId'] == feed['id'])
          .toList();
      for (final name in [
        'transport_routes',
        'transport_stops',
        'transport_services',
      ]) {
        final refs = name == 'transport_routes'
            ? feedTrips.map((t) => t.data['routeId'] as String).toSet()
            : name == 'transport_services'
            ? feedTrips.map((t) => t.data['serviceId'] as String).toSet()
            : {
                ...selected,
                ...feedTrips.expand((t) => t.times.map((s) => s.stopId)),
              };
        for (final id in refs) {
          final d = await record(collection(feed, name), id);
          if (d == null) continue;
          switch (name) {
            case 'transport_routes':
              routes[id] = TransportRoute(id, d);
            case 'transport_services':
              services[id] = TransportService(id, d);
            case 'transport_stops':
              stops[id] = TransportStop(id, d);
          }
        }
      }
      final zones = <String>{
        '*',
        ...stops.values
            .where((s) => selected.contains(s.id))
            .map((s) => s.data['zoneId'])
            .whereType<String>(),
      };
      for (final zone in zones) {
        for (final r in await all(
          collection(feed, 'transport_fares'),
          field: 'originZones',
          value: zone,
          array: true,
        )) {
          fares[r['id'] as String] = TransportFare(r['id'] as String, r);
        }
      }
    }
    return TransportData(
      stops.values.toList(),
      routes.values.toList(),
      trips.values.toList(),
      services.values.toList(),
      fares.values.toList(),
    );
  }
}
