import 'package:sightseeing_matching_app/data/departure_places.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/repository/settings_repository.dart';
import 'package:sightseeing_matching_app/state/conditions_step_state.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:sightseeing_matching_app/state/settings_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'package:sightseeing_matching_app/service/recommendation_service.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot, reveal, answerQuestions, enterDetails;

void main() {
  testWidgets(
    'offline map remains interactive; pin requires explicit confirmation',
    (tester) async {
      final container = await boot(tester);
      await tester.tap(find.text('新しい旅を探す'));
      await tester.pumpAndSettle();
      await answerQuestions(tester);
      final interests = container.read(discoveryProvider).interests;
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('地図から選ぶ'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byType(FlutterMap));
      expect(find.text('地図画像を表示できません。出発地の選択ボタンをご利用ください。'), findsOneWidget);
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      final oldZoom = controller.camera.zoom;
      await tester.tap(find.byTooltip('地図を拡大'));
      await tester.pumpAndSettle();
      expect(controller.camera.zoom, greaterThan(oldZoom));
      await tester.tap(find.byTooltip('地図を縮小'));
      await tester.pumpAndSettle();
      controller.move(departureNamed('小樽駅')!.point, controller.camera.zoom);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-pin-otaru')));
      await tester.pumpAndSettle();
      expect(container.read(conditionsStepProvider), 0);
      expect(container.read(searchDraftProvider).origin, '小樽駅');
      await tester.tap(find.text('この出発地にする'));
      await tester.pumpAndSettle();
      expect(find.text('どうやって旅する？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('travel-car')));
      await tester.pumpAndSettle();
      expect(find.text('どのくらい旅する？'), findsOneWidget);
      expect(
        container.read(discoveryProvider).interests.choices,
        interests.choices,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(container.read(searchDraftProvider).transport, TravelMode.car);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('どこから旅を始める？'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(container.read(discoveryProvider).question, 2);
      expect(container.read(discoveryProvider).answers, [0, 0]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('exactly four departure buttons form two rows and confirm once', (
    tester,
  ) async {
    final container = await boot(tester);
    await tester.tap(find.text('新しい旅を探す'));
    await tester.pumpAndSettle();
    await answerQuestions(tester);
    const names = ['札幌駅', '新千歳空港', '小樽駅', '旭川駅'];
    final rects = [
      for (final name in names)
        tester.getRect(find.byKey(ValueKey('origin-chip-$name'))),
    ];
    expect(rects[0].top, rects[1].top);
    expect(rects[2].top, rects[3].top);
    expect(rects[2].top, greaterThan(rects[0].bottom));
    expect(rects[1].left, greaterThan(rects[0].right));
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FlutterMap), findsNothing);
    for (final name in names) {
      await tester.tap(find.byKey(ValueKey('origin-chip-$name')));
      await tester.pumpAndSettle();
      expect(container.read(searchDraftProvider).origin, name);
      expect(container.read(conditionsStepProvider), 1);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('地図から選ぶ'));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    await tester.tap(find.text('地図から選ぶ'));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsNothing);
    final point = tester.getCenter(
      find.byKey(const ValueKey('origin-chip-小樽駅')),
    );
    await tester.tapAt(point);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(container.read(conditionsStepProvider), 1);
    final modePoint = tester.getCenter(
      find.byKey(const ValueKey('travel-either')),
    );
    await tester.tapAt(modePoint);
    await tester.tapAt(modePoint);
    await tester.pumpAndSettle();
    expect(container.read(conditionsStepProvider), 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'duration is four one-tap choices and final save searches with all entered values',
    (tester) async {
      final storage = MemorySettingsStorage();
      final container = await boot(tester, storage: storage);
      await tester.tap(find.text('新しい旅を探す'));
      await tester.pumpAndSettle();
      await answerQuestions(tester);
      await tester.tap(find.byKey(const ValueKey('origin-chip-小樽駅')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('travel-either')));
      await tester.pumpAndSettle();
      expect(find.text('STEP 3/4'), findsOneWidget);
      expect(find.text('詳細設定をスキップ'), findsNothing);
      final periods = ['halfDay', 'day', 'overnight', 'longer'];
      final rects = [
        for (final p in periods)
          tester.getRect(find.byKey(ValueKey('length-$p'))),
      ];
      expect(rects[0].top, rects[1].top);
      expect(rects[2].top, rects[3].top);
      for (final period in periods) {
        await tester.tap(find.byKey(ValueKey('length-$period')));
        await tester.pumpAndSettle();
        expect(container.read(conditionsStepProvider), 3);
        expect(find.text('誰と旅する？'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'この条件で探す'),
              )
              .onPressed,
          isNull,
        );
        if (period != periods.last) {
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
        }
      }
      await tester.tap(find.byKey(const ValueKey('company-family')));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
      await reveal(tester, find.text('さらに細かく設定'));
      await tester.tap(find.text('さらに細かく設定'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('total-budget')));
      await tester.drag(
        find.byKey(const ValueKey('total-budget')),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('少なめ'));
      await tester.tap(find.text('少なめ'));
      await tester.pumpAndSettle();
      final filters = container.read(searchDraftProvider);
      expect(filters.length, TripLength.longer);
      expect(filters.company, Company.family);
      expect(filters.walking, Walking.light);
      await tester.tap(find.text('条件を保存して検索'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).requireValue.presets, isEmpty);
      expect(container.read(settingsProvider).requireValue.lastSearch, isNull);
      final before = DateTime.now().toUtc();
      await tester.tap(find.text('条件を保存して検索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '編集した条件');
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      final settings = await LocalSettingsRepository(storage: storage).load();
      expect(settings.presets.single.conditions.toJson(), filters.toJson());
      expect(settings.lastSearch!.conditions.toJson(), filters.toJson());
      expect(settings.lastSearch!.searchedAt.isUtc, isTrue);
      expect(settings.lastSearch!.searchedAt.isBefore(before), isFalse);
      expect(container.read(tripProvider).travelDate, isNull);
      expect(container.read(discoveryProvider).step, 3);
      final expected = RecommendationService().recommend('食', [
        0,
        0,
      ], filters: filters);
      expect(
        container.read(discoveryProvider).deck.map((e) => e.id),
        expected.map((e) => e.id),
      );
      expect(settings.profile.budget, 10000);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed save-and-search is atomic and can be retried', (
    tester,
  ) async {
    final storage = MemorySettingsStorage();
    const preset = SearchConditions(
      origin: '札幌駅',
      budget: 23000,
      maxMinutes: 300,
      company: Company.couple,
    );
    await LocalSettingsRepository(storage: storage).save(
      SavedSettings(
        presets: const [
          SearchPreset(id: 'p', name: '以前の条件', conditions: preset),
        ],
      ),
    );
    final container = await boot(tester, storage: storage);
    await tester.tap(find.text('プロフィール'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('読み込み'));
    await tester.tap(find.text('読み込み'));
    await tester.pumpAndSettle();
    await answerQuestions(tester);
    expect(container.read(searchDraftProvider).toJson(), preset.toJson());
    await enterDetails(tester, company: 'couple');
    storage.failWrite = true;
    await tester.tap(find.text('条件を保存して検索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '再保存');
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(container.read(discoveryProvider).step, 1);
    expect(container.read(settingsProvider).requireValue.lastSearch, isNull);
    expect(container.read(settingsProvider).requireValue.presets.length, 1);
    expect(find.textContaining('検索条件を保存できませんでした'), findsOneWidget);
    storage.failWrite = false;
    await tester.tap(find.text('条件を保存して検索'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    final restored = await LocalSettingsRepository(storage: storage).load();
    expect(restored.presets.length, 2);
    expect(restored.lastSearch!.conditions.maxMinutes, 300);
    expect(restored.presets.first.conditions.toJson(), preset.toJson());
    expect(container.read(discoveryProvider).step, 3);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets(
      'small Android layout at $size',
      (tester) async {
        final container = await boot(tester);
        await tester.binding.setSurfaceSize(size);
        await tester.tap(find.text('新しい旅を探す'));
        await tester.pumpAndSettle();
        await answerQuestions(tester);
        for (final name in ['札幌駅', '新千歳空港', '小樽駅', '旭川駅']) {
          expect(
            find.byKey(ValueKey('origin-chip-$name')).hitTestable(),
            findsOneWidget,
          );
        }
        await tester.tap(find.byKey(const ValueKey('origin-chip-旭川駅')));
        await tester.pumpAndSettle();
        await reveal(tester, find.byKey(const ValueKey('travel-either')));
        await tester.tap(find.byKey(const ValueKey('travel-either')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('length-day')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('company-solo')));
        await tester.pumpAndSettle();
        expect(find.text('この条件で探す').hitTestable(), findsOneWidget);
        expect(find.text('条件を保存して検索').hitTestable(), findsOneWidget);
        expect(find.text('詳細設定をスキップ'), findsNothing);
        expect(find.byType(CalendarDatePicker), findsNothing);
        expect(container.read(conditionsStepProvider), 3);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({TargetPlatform.android}),
    );
  }
}
