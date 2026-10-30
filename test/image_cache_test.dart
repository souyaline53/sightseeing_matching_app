import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sightseeing_matching_app/service/display_image.dart';
import 'package:sightseeing_matching_app/service/image_cache/cache_store.dart';
import 'package:sightseeing_matching_app/service/image_cache/cloud_photo_cache.dart';
import 'package:sightseeing_matching_app/screen/recommendation/curiosity_question_flow.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot;

class MemoryPhotoStore implements PhotoCacheStore {
  final values = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => values[key];
  @override
  Future<void> write(String key, Uint8List bytes) async {
    values[key] = bytes;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

void main() {
  initializeCatalogTests();
  test(
    'uploaded display image is a <=200KB oriented static JPEG without alpha',
    () async {
      final source = img.Image(width: 1400, height: 1000, numChannels: 3);
      final random = Random(12);
      for (final pixel in source) {
        pixel.setRgb(
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      }
      final original = img.encodeJpg(source, quality: 95);
      expect(original.length, greaterThan(maxDisplayImageBytes));
      final bytes = await createDisplayImage(original);
      expect(bytes.length, lessThanOrEqualTo(maxDisplayImageBytes));
      final decoded = img.decodeJpg(bytes)!;
      expect(max(decoded.width, decoded.height), lessThanOrEqualTo(1280));
      final rotated = img.Image(width: 20, height: 10, numChannels: 3);
      rotated.exif.imageIfd.orientation = 6;
      final upright = img.decodeJpg(
        encodeDisplayImage(img.encodeJpg(rotated)),
      )!;
      expect(upright.width, 10);
      expect(upright.height, 20);
      final transparent = img.Image(width: 10, height: 10, numChannels: 4);
      final white = img.decodeJpg(
        encodeDisplayImage(img.encodePng(transparent)),
      )!;
      expect(white.getPixel(0, 0).r, greaterThan(230));
      expect(() => encodeDisplayImage(Uint8List(0)), throwsStateError);
    },
  );
  test(
    'same URL survives cache instances; changed URL downloads once; concurrent requests coalesce',
    () async {
      final store = MemoryPhotoStore();
      var requests = 0;
      Future<Uint8List> download(String url) async {
        requests++;
        await Future<void>.delayed(Duration.zero);
        return testImageBytes;
      }

      final first = CloudPhotoCache(store: store, download: download);
      await Future.wait(
        List.generate(
          5,
          (_) => first.load('https://example.test/photo-v1.jpg'),
        ),
      );
      expect(requests, 1);
      final second = CloudPhotoCache(store: store, download: download);
      await second.load('https://example.test/photo-v1.jpg');
      expect(requests, 1);
      await second.load('https://example.test/photo-v2.jpg');
      expect(requests, 2);
      await second.load('https://example.test/photo-v2.jpg');
      expect(requests, 2);
      expect(store.values, hasLength(2));
    },
  );
  test('failed downloads are retryable and never persist as images', () async {
    final store = MemoryPhotoStore();
    var calls = 0;
    final cache = CloudPhotoCache(
      store: store,
      download: (url) async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return testImageBytes;
      },
    );
    await expectLater(
      cache.load('https://example.test/image'),
      throwsStateError,
    );
    expect(store.values, isEmpty);
    await cache.load('https://example.test/image');
    expect(calls, 2);
  });
  testWidgets(
    'all curiosity questions use icons and never mount image widgets',
    (tester) async {
      await boot(tester);
      await tester.tap(find.text('新しい旅を探す'));
      await tester.pumpAndSettle();
      final flow = find.byType(CuriosityQuestionFlow);
      expect(
        find.descendant(of: flow, matching: find.byType(Image)),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('question-icon-food')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mood-food')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: flow, matching: find.byType(Image)),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('reason-food_hidden')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('question-icon-roots_history')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: flow, matching: find.byType(Image)),
        findsNothing,
      );
    },
  );
}
