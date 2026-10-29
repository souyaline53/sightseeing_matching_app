import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/repository/mock_catalog_repository.dart';
import 'package:sightseeing_matching_app/service/photo_source.dart';

const spotPath = 'assets/mock_data/sightseeing_spot/';
const transitPath = 'assets/mock_data/transit/';
String spot({
  String id = 'new',
  int order = 10,
  String photo = '../images/new.jpg',
}) =>
    '''
# 新しい体験
- id: $id
- order: $order
- area: 札幌
- category: 自然
- minutes: 60
- access_minutes: 45

## 写真
${photo.isEmpty ? '' : '![写真]($photo)'}
## 紹介
短い紹介
## ストーリー
最初の段落。

次の段落。
## 意外な魅力
意外な発見。
## 補足写真
![補足](../images/detail.jpg)
''';
String transit({
  String id = 'bus',
  String spotId = '*',
  String departure = '08:10',
  String arrival = '09:20',
  int step = 120,
}) =>
    '''
# バスのサンプル
- id: $id
- order: 10
- position: any
- spot_id: $spotId
- mode: $id
- departure: $departure
- arrival: $arrival
- step_minutes: $step
- transfer: 乗換なし（仮）
- walking: 徒歩10分（仮）
- fare: 500円（仮）
## 注意
サンプル時刻・実際の運行情報ではありません。
''';

class MapBundle extends CachingAssetBundle {
  final Map<String, String> files;
  MapBundle(this.files);
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(files[key]!)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'asset manifest loads all Markdown records and offline photos',
    (tester) async {
      await tester.runAsync(() async {
        final catalog = await MarkdownMockCatalogRepository().load();
        expect(catalog.experiences, hasLength(10));
        expect(catalog.transit, hasLength(2));
        expect(catalog.experiences.first.id, 'melon');
        for (final experience in catalog.experiences) {
          expect(experience.photo, startsWith('assets/mock_data/images/'));
          expect(
            (await rootBundle.load(experience.photo)).lengthInBytes,
            greaterThan(1000),
          );
          expect(photoSource(experience.imageUrl), isA<AssetImage>());
        }
        final legs = catalog.sampleTransit('小樽駅', catalog.experiences);
        expect(legs.first.from, '小樽駅');
        expect(legs.first.departure, '08:10');
        expect(legs[1].from, catalog.experiences.first.area);
        expect(legs[1].departure, '10:10');
        expect(legs.last.departure, startsWith('+1日'));
        expect(legs.every((leg) => leg.note.contains('サンプル')), isTrue);
      });
    },
    timeout: const Timeout(Duration(seconds: 30)),
    // The Chrome test harness does not provide PlatformAssetBundle responses.
    // Real bundled assets are checked on VM and in the served release build.
    skip: kIsWeb,
  );

  test(
    'new Markdown files are picked up, ordered and parsed without Dart records',
    () async {
      final files = {
        '${spotPath}second.md': spot(id: 'second', order: 20),
        '${spotPath}first.md': spot(id: 'first', order: 1),
        '${transitPath}generic.md': transit(),
        '${transitPath}specific.md': transit(id: 'specific', spotId: 'second'),
        'assets/mock_data/README.md': 'ignored documentation',
        '${spotPath}template.md.example': 'ignored template',
      };
      final catalog = await MarkdownMockCatalogRepository(
        bundle: MapBundle(files),
      ).loadFiles(files.keys);
      expect(catalog.experiences.map((e) => e.id), ['first', 'second']);
      expect(
        catalog.experiences.first.photo,
        'assets/mock_data/images/new.jpg',
      );
      expect(
        catalog.experiences.first.additionalPhotos.single,
        'assets/mock_data/images/detail.jpg',
      );
      expect(catalog.experiences.first.story, '最初の段落。\n\n次の段落。');
      expect(catalog.experiences.first.accessMinutes, 45);
      expect(
        catalog.sampleTransit('札幌駅', catalog.experiences)[1].mode,
        'specific',
      );
      expect(
        () => catalog.experiences.add(catalog.experiences.first),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'missing photos and transit remain explicit; remote and legacy photos still work',
    () async {
      final files = {'${spotPath}a.md': spot(photo: '')};
      final catalog = await MarkdownMockCatalogRepository(
        bundle: MapBundle(files),
      ).loadFiles(files.keys);
      expect(catalog.experiences.single.photo, '');
      expect(
        catalog.sampleTransit('札幌駅', catalog.experiences).single.mode,
        '交通サンプル未登録',
      );
      final remote = MarkdownRecord.parse(
        '${spotPath}a.md',
        spot(photo: 'https://example.com/photo.jpg'),
      ).toExperience();
      expect(photoSource(remote.imageUrl), isA<NetworkImage>());
      final legacy = Experience.fromJson(
        {...remote.toJson(), 'photo': 'photo-old'}
          ..remove('additionalPhotos')
          ..remove('accessMinutes'),
      );
      expect(legacy.imageUrl, contains('images.unsplash.com/photo-old'));
      expect(legacy.additionalPhotos, isEmpty);
      expect(legacy.accessMinutes, 120);
      expect(
        Experience.fromJson(remote.toJson()).additionalPhotos,
        remote.additionalPhotos,
      );
    },
  );

  test(
    'invalid fields and duplicate IDs report the offending filename',
    () async {
      var files = {'${spotPath}a.md': spot(), '${spotPath}b.md': spot()};
      await expectLater(
        MarkdownMockCatalogRepository(
          bundle: MapBundle(files),
        ).loadFiles(files.keys),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'path',
            contains('b.md'),
          ),
        ),
      );
      expect(
        () => MarkdownRecord.parse(
          '${spotPath}bad.md',
          spot().replaceAll('- minutes: 60', '- minutes: no'),
        ).toExperience(),
        throwsFormatException,
      );
      expect(
        () => MarkdownRecord.parse(
          '${spotPath}bad.md',
          spot().replaceAll('- area: 札幌', ''),
        ).toExperience(),
        throwsFormatException,
      );
      expect(
        () => MarkdownRecord.parse(
          '${spotPath}bad.md',
          spot(photo: '../../../private.jpg'),
        ).toExperience(),
        throwsFormatException,
      );
      expect(
        () => MarkdownRecord.parse(
          '${transitPath}bad.md',
          transit(departure: '25:10'),
        ).toTransit(),
        throwsFormatException,
      );
    },
  );

  test('overnight sample times carry into the next day', () {
    final record = MarkdownRecord.parse(
      '${transitPath}night.md',
      transit(departure: '23:30', arrival: '00:10', step: 0),
    ).toTransit();
    expect(record.arrivalMinutes - record.departureMinutes, 40);
  });
}
