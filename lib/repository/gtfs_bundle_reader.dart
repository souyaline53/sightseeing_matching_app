import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../model/transport.dart';
import '../service/transport/gtfs_asset_loader.dart';
import 'transport_repository.dart';

String gtfsShard(String value) =>
    sha256.convert(utf8.encode(value)).toString().substring(0, 2);

class GtfsBundleReader {
  final Json feed;
  final GtfsAssetLoader loader;
  Json? _manifest;
  GtfsBundleReader(this.feed, this.loader);
  String get prefix =>
      'transport_data/${feed['id']}/${feed['activeVersionId']}';
  Future<Json> manifest() async {
    if (_manifest != null) return _manifest!;
    final d = Map<String, dynamic>.from(feed['distribution'] as Map);
    if (d['manifestPath'] != '$prefix/manifest.json') {
      throw const FormatException('交通データ配信先が一致しません');
    }
    final result = Map<String, dynamic>.from(
      await loader.load(
            d['manifestPath'] as String,
            checksum: d['manifestChecksum'] as String,
            rawBytes: d['manifestBytes'] as int,
            gzip: false,
          )
          as Map,
    );
    if (result['formatVersion'] != 2 ||
        result['feedId'] != feed['id'] ||
        result['versionId'] != feed['activeVersionId']) {
      throw const FormatException('交通データの版が一致しません');
    }
    return _manifest = result;
  }

  Future<Json> asset(String name) async {
    if (name.contains('..') ||
        name.startsWith('/') ||
        !RegExp(r'^[a-zA-Z0-9_/-]+\.json\.gz$').hasMatch(name)) {
      throw const FormatException('交通データ名が不正です');
    }
    final m = await manifest(), descriptor = (m['assets'] as Map)[name] as Map?;
    if (descriptor == null) return {};
    final value = await loader.load(
      '$prefix/$name',
      checksum: descriptor['checksum'] as String,
      rawBytes: descriptor['rawBytes'] as int,
    );
    return Map<String, dynamic>.from(value as Map);
  }

  List<Json> rows(Json value, String key) => (value[key] as List? ?? [])
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
  Future<List<Json>> agencies() async =>
      rows(await asset('catalog.json.gz'), 'agencies');
  Future<List<Json>> routes(String agencyId) async => rows(
    await asset('catalog.json.gz'),
    'routes',
  ).where((r) => r['agencyId'] == agencyId).toList();
  Future<Json> routeSummary(String routeId) async {
    final route = rows(
      await asset('catalog.json.gz'),
      'routes',
    ).where((r) => r['id'] == routeId).firstOrNull;
    return route == null ? {} : asset(route['routeFile'] as String);
  }

  Future<List<Json>> routeStops(String routeId) async {
    final stops = rows(await routeSummary(routeId), 'stops');
    final descriptor = (feed['distribution'] as Map)['platformLabels'] as Map?;
    if (descriptor == null) return stops;
    final path = descriptor['path'] as String;
    if (!path.startsWith('$prefix/stop-labels-') ||
        !RegExp(r'/stop-labels-[0-9a-f]{64}\.json\.gz$').hasMatch(path)) {
      throw const FormatException('乗り場案内の配信先が不正です');
    }
    final labels = Map<String, dynamic>.from(
      await loader.load(
            path,
            checksum: descriptor['checksum'] as String,
            rawBytes: descriptor['rawBytes'] as int,
          )
          as Map,
    );
    if (labels['feedId'] != feed['id'] ||
        labels['versionId'] != feed['activeVersionId']) {
      throw const FormatException('乗り場案内の版が一致しません');
    }
    return stops.map((s) {
      final byRoute = (labels['stops'] as Map)[s['id']] as Map?;
      final directions = byRoute?[routeId] as Map?;
      return {
        ...s,
        'stopDestinations': directions?['departures'] ?? <String>[],
        'arrivalOrigins': directions?['arrivals'] ?? <String>[],
      };
    }).toList();
  }

  Future<List<Json>> findStops(String name) async => rows(
    await asset('stop-names.json.gz'),
    'stops',
  ).where((s) => s['name'] == name).toList();
  Future<TransportData> load(Set<String> selected) async {
    final stops = <String, TransportStop>{},
        routes = <String, TransportRoute>{},
        trips = <String, TransportTrip>{},
        services = <String, TransportService>{},
        fares = <String, Json>{};
    for (final s in selected.map(gtfsShard).toSet()) {
      for (final r in rows(await asset('stops/$s.json.gz'), 'stops')) {
        if (selected.contains(r['id'])) {
          stops[r['id'] as String] = TransportStop(r['id'] as String, r);
        }
      }
    }
    final routeIds = stops.values
        .expand((s) => (s.data['routeIds'] as List? ?? []).cast<String>())
        .toSet();
    for (final routeId in routeIds) {
      final summary = await routeSummary(routeId);
      if (summary.isEmpty) continue;
      final route = Map<String, dynamic>.from(summary['route'] as Map);
      routes[routeId] = TransportRoute(routeId, route);
      for (final r in rows(summary, 'stops')) {
        stops[r['id'] as String] = TransportStop(r['id'] as String, r);
      }
      final pageNames = (summary['tripPages'] as List)
          .where((p) => (p['stopIds'] as List).any(selected.contains))
          .map((p) => p['file'] as String)
          .toSet();
      for (final page in pageNames) {
        final data = await asset(page);
        for (final r in rows(data, 'trips')) {
          if ((r['stopIds'] as List).any(selected.contains)) {
            trips[r['id'] as String] = TransportTrip(r['id'] as String, r);
          }
        }
        for (final r in rows(data, 'services')) {
          services[r['id'] as String] = TransportService(r['id'] as String, r);
        }
      }
    }
    final zones = {
      '*',
      ...stops.values
          .where((s) => selected.contains(s.id))
          .map((s) => s.data['zoneId'])
          .whereType<String>(),
    };
    final shards = zones.map(gtfsShard).toSet();
    final m = await manifest();
    for (final name in (m['assets'] as Map).keys.cast<String>().where(
      (name) =>
          RegExp(r'^fares/[0-9a-f]{2}-\d+\.json\.gz$').hasMatch(name) &&
          shards.contains(name.substring(6, 8)),
    )) {
      for (final r in rows(await asset(name), 'fares')) {
        final id = r['id'] as String;
        final matching = (r['rules'] as List)
            .where((rule) => zones.contains((rule as Map)['originId'] ?? '*'))
            .toList();
        if (matching.isEmpty) continue;
        fares.putIfAbsent(id, () => {...r, 'rules': <dynamic>[]});
        (fares[id]!['rules'] as List).addAll(matching);
      }
    }
    return TransportData(
      stops.values.toList(),
      routes.values.toList(),
      trips.values.toList(),
      services.values.toList(),
      fares.entries.map((e) => TransportFare(e.key, e.value)).toList(),
    );
  }
}
