@TestOn('vm')
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/service/image_cache/cache_store_io.dart';
import 'package:sightseeing_matching_app/service/image_cache/cloud_photo_cache.dart';
import 'test_support.dart';

void main() {
  test(
    'file cache survives cache instances without another download',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'tabisaki-image-cache-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      var requests = 0;
      final first = CloudPhotoCache(
        store: FilePhotoCacheStore(directory: () async => dir),
        download: (url) async {
          requests++;
          return testImageBytes;
        },
      );
      await first.load('https://example.test/photo');
      final second = CloudPhotoCache(
        store: FilePhotoCacheStore(directory: () async => dir),
        download: (url) async {
          requests++;
          return testImageBytes;
        },
      );
      expect(await second.load('https://example.test/photo'), testImageBytes);
      expect(requests, 1);
    },
  );
}
