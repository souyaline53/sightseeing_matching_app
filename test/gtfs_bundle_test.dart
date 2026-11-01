import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/repository/gtfs_bundle_reader.dart';
import 'package:sightseeing_matching_app/service/transport/gtfs_asset_loader.dart';
import 'package:sightseeing_matching_app/service/transport/asset_cache_store.dart';
import 'package:sightseeing_matching_app/service/transport/transport_search.dart';
import 'package:sightseeing_matching_app/model/transport.dart';

class MemoryAssetStore implements TransportAssetStore {
  final data = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => data[key];
  @override
  Future<void> write(String key, Uint8List value) async {
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    data.remove(key);
  }
}

void main() {
  late Directory dir;
  late Map<String, dynamic> feed;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('tabisaki-bundle-');
    final p = await Process.run('node', [
      'functions/test_support/build_bundle.cjs',
      dir.path,
    ]);
    expect(p.exitCode, 0, reason: '${p.stderr}');
    feed =
        jsonDecode(await File('${dir.path}/feed.json').readAsString())
            as Map<String, dynamic>;
  });
  tearDownAll(() async => dir.delete(recursive: true));
  test(
    'Storage browse fetches no trip pages; timetable search keeps intermediate stops, calendar and zone fares',
    () async {
      final requested = <String>[];
      final store = MemoryAssetStore();
      final loader = GtfsAssetLoader((path, limit) async {
        requested.add(path);
        return File('${dir.path}/$path').readAsBytes();
      }, store: store);
      final reader = GtfsBundleReader(feed, loader);
      final agencies = await reader.agencies();
      final routes = await reader.routes(agencies.single['id'] as String);
      final stops = await reader.routeStops(routes.single['id'] as String);
      expect(stops.length, 3);
      expect(stops.first['stopDestinations'], ['同名']);
      expect(requested.any((p) => p.contains('/trips-')), false);
      String id(String raw) =>
          'feed~${base64Url.encode(utf8.encode(raw)).replaceAll('=', '')}';
      final data = await reader.load({id('01'), id('03')});
      final candidates = findCandidates(
        trips: data.trips,
        routes: data.routes,
        services: data.services,
        fares: data.fares,
        stops: data.stops,
        from: [
          AccessStop({'stopId': id('01')}),
        ],
        to: [
          AccessStop({'stopId': id('03')}),
        ],
        date: DateTime(2026, 1, 5),
      );
      expect(candidates.length, 1);
      expect(candidates.single.fare, 500);
      expect(candidates.single.trip.times.length, 3);
      expect(candidates.single.boarding.data['departureSeconds'], 87031);
      final count = requested.length;
      await reader.load({id('01'), id('03')});
      expect(requested.length, count);
      final newLoader = GtfsAssetLoader(
        (p, l) async => throw StateError('network disabled'),
        store: store,
      );
      expect(
        (await GtfsBundleReader(
          feed,
          newLoader,
        ).load({id('01'), id('03')})).trips.length,
        1,
      );
    },
  );
  test(
    'corrupt persistent cache is refetched; corrupt downloads are rejected before caching',
    () async {
      final store = MemoryAssetStore();
      final bytes = Uint8List.fromList(utf8.encode('{"valid":true}'));
      final checksum = sha256.convert(bytes).toString();
      var count = 0;
      final a = GtfsAssetLoader((p, l) async {
        count++;
        return bytes;
      }, store: store);
      expect(
        await a.load(
          'test',
          checksum: checksum,
          rawBytes: bytes.length,
          gzip: false,
        ),
        {'valid': true},
      );
      store.data.updateAll((k, v) => Uint8List.fromList([0]));
      final b = GtfsAssetLoader((p, l) async {
        count++;
        return bytes;
      }, store: store);
      await b.load(
        'test',
        checksum: checksum,
        rawBytes: bytes.length,
        gzip: false,
      );
      expect(count, 2);
      final bad = GtfsAssetLoader(
        (p, l) async => Uint8List.fromList([1]),
        store: MemoryAssetStore(),
      );
      expect(
        () => bad.load(
          'bad',
          checksum: checksum,
          rawBytes: bytes.length,
          gzip: false,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'manifest rejects an incompatible version before querying data',
    () async {
      final reader = GtfsBundleReader(
        {...feed, 'activeVersionId': 'other'},
        GtfsAssetLoader(
          (p, l) async => throw StateError('should not download'),
          store: MemoryAssetStore(),
        ),
      );
      expect(reader.manifest, throwsFormatException);
    },
  );
}
