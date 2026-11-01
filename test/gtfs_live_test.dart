// Read-only deployment smoke test. Opt in explicitly; normal test runs stay offline.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/model/stop_selection.dart';
import 'package:sightseeing_matching_app/repository/gtfs_bundle_reader.dart';
import 'package:sightseeing_matching_app/service/transport/asset_cache_store.dart';
import 'package:sightseeing_matching_app/service/transport/gtfs_asset_loader.dart';
import 'package:sightseeing_matching_app/service/transport/transport_search.dart';

class _Store implements TransportAssetStore {
  final rows = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => rows[key];
  @override
  Future<void> write(String key, Uint8List bytes) async {
    rows[key] = bytes;
  }

  @override
  Future<void> remove(String key) async {
    rows.remove(key);
  }
}

Object? _decode(Map<String, dynamic> v) {
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('integerValue')) {
    return int.parse(v['integerValue'] as String);
  }
  if (v.containsKey('doubleValue')) return v['doubleValue'];
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('mapValue')) {
    return (v['mapValue']['fields'] as Map? ?? {}).map(
      (k, x) =>
          MapEntry(k.toString(), _decode(Map<String, dynamic>.from(x as Map))),
    );
  }
  if (v.containsKey('arrayValue')) {
    return (v['arrayValue']['values'] as List? ?? [])
        .map((x) => _decode(Map<String, dynamic>.from(x as Map)))
        .toList();
  }
  return null;
}

void main() {
  const enabled = bool.fromEnvironment('GTFS_LIVE_TEST');
  const project = 'sightseeing-matching-prototype';
  const firestore =
      'https://firestore.googleapis.com/v1/projects/$project/databases/(default)/documents';
  const storage =
      'https://firebasestorage.googleapis.com/v0/b/$project.firebasestorage.app/o';
  for (final id in ['yutetsu_bus', 'hokkaido_chuo']) {
    test(
      'public $id: metadata, Storage browse, intermediate timetable, calendar, cache and private source',
      () async {
        final client = http.Client();
        addTearDown(client.close);
        final response = await client
            .get(Uri.parse('$firestore/transport_feeds/$id'))
            .timeout(const Duration(seconds: 20));
        expect(response.statusCode, 200);
        final fields = (jsonDecode(response.body)['fields'] as Map).map(
          (k, v) => MapEntry(
            k.toString(),
            _decode(Map<String, dynamic>.from(v as Map)),
          ),
        );
        final feed = <String, dynamic>{...fields, 'id': id};
        expect(feed['importStatus'], 'ready');
        expect((feed['distribution'] as Map)['formatVersion'], 2);
        final requests = <String>[];
        final loader = GtfsAssetLoader(
          (path, limit) async {
            requests.add(path);
            final r = await client
                .get(
                  Uri.parse('$storage/${Uri.encodeComponent(path)}?alt=media'),
                )
                .timeout(const Duration(seconds: 20));
            expect(r.statusCode, 200, reason: path);
            expect(r.bodyBytes.length <= limit, true);
            return r.bodyBytes;
          },
          store: _Store(),
          namespace: project,
        );
        final reader = GtfsBundleReader(feed, loader);
        final agency = (await reader.agencies()).first;
        final routes = await reader.routes(agency['id'] as String);
        expect(routes, isNotEmpty);
        expect(requests.any((p) => p.contains('/trips-')), false);
        TransportTrip? chosen;
        StopTime? boarding, alighting;
        // Some express routes permit pickup only until the final stop. Find an
        // actual intermediate segment whose pickup AND dropoff are allowed.
        for (final route in routes) {
          final summary = await reader.routeSummary(route['id'] as String);
          final stopRows = {
            for (final r in summary['stops'] as List) (r as Map)['id']: r,
          };
          for (final descriptor in summary['tripPages'] as List) {
            final page = await reader.asset(descriptor['file'] as String);
            var score = 1 << 30;
            for (final row in page['trips'] as List) {
              final trip = TransportTrip(
                (row as Map)['id'] as String,
                Map<String, dynamic>.from(row),
              );
              final times = trip.times;
              final intermediate = times
                  .skip(1)
                  .take(times.length > 2 ? times.length - 2 : 0)
                  .toList();
              for (final start in intermediate.where(
                (s) => s.pickup && s.departure != null,
              )) {
                for (final end in intermediate.where(
                  (s) =>
                      s.dropoff &&
                      s.arrival != null &&
                      s.sequence > start.sequence,
                )) {
                  final weight =
                      ((stopRows[start.stopId]?['routeIds'] as List?)?.length ??
                          999) +
                      ((stopRows[end.stopId]?['routeIds'] as List?)?.length ??
                          999);
                  if (weight < score) {
                    score = weight;
                    chosen = trip;
                    boarding = start;
                    alighting = end;
                  }
                }
              }
            }
            if (chosen != null) break;
          }
          if (chosen != null) break;
        }
        expect(
          chosen,
          isNotNull,
          reason: 'A real intermediate-stop segment must be available',
        );
        final data = await reader.load({boarding!.stopId, alighting!.stopId});
        final service = data.services.firstWhere(
          (s) => s.id == chosen!.data['serviceId'],
        );
        DateTime? date;
        for (final day in (service.data['addedDates'] as List? ?? [])) {
          final d = DateTime.parse(day as String);
          if (service.operates(d)) {
            date = d;
            break;
          }
        }
        final first = DateTime.parse(
          service.data['validFrom'] as String? ?? '2026-11-01',
        );
        for (var n = 0; date == null && n < 370; n++) {
          final d = first.add(Duration(days: n));
          if (service.operates(d)) date = d;
        }
        expect(date, isNotNull);
        final result = findCandidates(
          trips: data.trips,
          routes: data.routes,
          services: data.services,
          stops: data.stops,
          fares: data.fares,
          from: [
            AccessStop({'stopId': boarding.stopId}),
          ],
          to: [
            AccessStop({'stopId': alighting.stopId}),
          ],
          date: date,
        );
        expect(
          result.any(
            (c) =>
                c.trip.id == chosen!.id &&
                c.boarding.sequence == boarding!.sequence &&
                c.alighting.sequence == alighting!.sequence,
          ),
          true,
        );
        final count = requests.length;
        await reader.load({boarding.stopId, alighting.stopId});
        expect(requests.length, count);
        final raw = '${feed['sourceDirectory']}/agency.txt';
        expect(
          (await client.get(
            Uri.parse('$storage/${Uri.encodeComponent(raw)}?alt=media'),
          )).statusCode,
          403,
        );
        // ignore: avoid_print
        print(
          '$id: routes=${routes.length}, candidates=${result.length}, Storage requests=${loader.requests}, bytes=${loader.downloadedBytes}, repeat network requests=0',
        );
      },
      skip: !enabled,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
  test(
    'published platform hints preserve both IDs and show actual opposite headsigns without trip downloads',
    () async {
      final client = http.Client();
      addTearDown(client.close);
      final response = await client.get(
        Uri.parse('$firestore/transport_feeds/yutetsu_bus'),
      );
      expect(response.statusCode, 200);
      final fields = (jsonDecode(response.body)['fields'] as Map).map(
        (k, v) => MapEntry(
          k.toString(),
          _decode(Map<String, dynamic>.from(v as Map)),
        ),
      );
      final feed = <String, dynamic>{...fields, 'id': 'yutetsu_bus'};
      expect((feed['distribution'] as Map)['platformLabels'], isNotNull);
      final requests = <String>[];
      final loader = GtfsAssetLoader((path, limit) async {
        requests.add(path);
        final r = await client.get(
          Uri.parse('$storage/${Uri.encodeComponent(path)}?alt=media'),
        );
        expect(r.statusCode, 200);
        return r.bodyBytes;
      }, store: _Store());
      final reader = GtfsBundleReader(feed, loader),
          agency = (await reader.agencies()).single;
      final route = (await reader.routes(
        agency['id'] as String,
      )).firstWhere((r) => r['name'] == '夕張市内線');
      final stops = await reader.routeStops(route['id'] as String);
      final group = groupStopSelections(
        stops,
      ).firstWhere((g) => g.first['name'] == '夕張高校');
      expect(group.length, 2);
      final outbound = group.firstWhere(
        (s) => s['stopId'] == 'S018100000300100',
      );
      final inbound = group.firstWhere(
        (s) => s['stopId'] == 'S018100000300200',
      );
      expect(outbound['stopDestinations'], contains('新夕張駅前'));
      expect(inbound['stopDestinations'], contains('夕張市石炭博物館'));
      expect(
        stops.firstWhere(
          (s) => s['stopId'] == 'S018100000400100',
        )['stopDestinations'],
        contains('夕張市石炭博物館'),
      );
      final saved = appendAccessStopSelections([], group);
      expect(saved.map((s) => s['stopId']).toSet().length, 2);
      expect(saved.every((s) => s['walkingMinutes'] == null), true);
      expect(requests.any((p) => p.contains('/trips-')), false);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'production callables reject non-admin requests',
    () async {
      for (final name in [
        'importTransport',
        'saveManualTransport',
        'transportSampleInventory',
      ]) {
        final r = await http
            .post(
              Uri.parse(
                'https://asia-northeast1-$project.cloudfunctions.net/$name',
              ),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'data': {}}),
            )
            .timeout(const Duration(seconds: 30));
        expect([401, 403].contains(r.statusCode), true, reason: name);
        expect(jsonDecode(r.body)['error'], isNotNull);
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
