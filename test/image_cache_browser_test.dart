@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/service/image_cache/cache_store_web.dart';
import 'package:sightseeing_matching_app/service/image_cache/cloud_photo_cache.dart';
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'browser Cache Storage reuses unchanged URL across cache objects without HTTP',
    () async {
      final store = BrowserPhotoCacheStore(
        name: 'tabisaki-test-${DateTime.now().microsecondsSinceEpoch}',
      );
      var requests = 0;
      Future<Uint8List> download(String url) async {
        requests++;
        return testImageBytes;
      }

      final first = CloudPhotoCache(store: store, download: download);
      await first.load('https://example.test/v1');
      final second = CloudPhotoCache(
        store: BrowserPhotoCacheStore(name: store.name),
        download: download,
      );
      expect(await second.load('https://example.test/v1'), testImageBytes);
      expect(requests, 1);
      await second.load('https://example.test/v2');
      expect(requests, 2);
      await first.evict('https://example.test/v1');
      await second.evict('https://example.test/v2');
    },
  );
}
