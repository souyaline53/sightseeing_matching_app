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
      await tester.tap(find.text('検索を開始する'));
      await tester.pumpAndSettle();
      await answerQuestions(tester);
      final interests = container.read(discoveryProvider).interests;
      await reveal(tester, find.byType(FlutterMap));
      expect(find.text('地図画像を表示できません。検索欄・候補からも選択できます。'), findsOneWidget);
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      final oldZoom = controller.camera.zoom;
      await tester.tap(find.byTooltip('地図を拡大'));
      await tester.pumpAndSettle();
      expect(controller.camera.zoom, greaterThan(oldZoom));
      await tester.tap(find.byTooltip('地図を縮小'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-pin-odori-bus')));
      await tester.pumpAndSettle();
      expect(container.read(conditionsStepProvider), 0);
      expect(container.read(searchDraftProvider).origin, contains('バス停'));
      await tester.tap(find.text('この出発地にする'));
      await tester.pumpAndSettle();
      expect(find.text('どうやって旅する？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('travel-car')));
      await tester.pumpAndSettle();
      expect(find.text('旅の条件を決めよう'), findsOneWidget);
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
  testWidgets(
    'chips and local search candidates confirm once, even with consecutive taps',
    (tester) async {
      final container = await boot(tester);
      await tester.tap(find.text('検索を開始する'));
      await tester.pumpAndSettle();
      await answerQuestions(tester);
      await tester.enterText(
        find.byKey(const ValueKey('search-origin')),
        'おたる',
      );
      await tester.pumpAndSettle();
      final resultPoint = tester.getCenter(
        find.byKey(const ValueKey('origin-result-otaru')),
      );
      await tester.tapAt(resultPoint);
      await tester.tapAt(resultPoint);
      await tester.pumpAndSettle();
      expect(container.read(conditionsStepProvider), 1);
      expect(container.read(searchDraftProvider).origin, '小樽駅');
      final modePoint = tester.getCenter(
        find.byKey(const ValueKey('travel-either')),
      );
      await tester.tapAt(modePoint);
      await tester.tapAt(modePoint);
      await tester.pumpAndSettle();
      expect(container.read(conditionsStepProvider), 2);
      expect(find.byType(PageView), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('search-origin')),
        '任意の地域',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('origin-free-text')));
      await tester.pumpAndSettle();
      expect(container.read(searchDraftProvider).origin, '任意の地域');
      expect(container.read(conditionsStepProvider), 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'skip restores initial detail filters, preserves chosen origin and mode, and records UTC',
    (tester) async {
      final storage = MemorySettingsStorage();
      await LocalSettingsRepository(storage: storage).save(
        SavedSettings(
          profile: const UserProfile(
            origin: '札幌駅',
            budget: 25000,
            walking: Walking.plenty,
          ),
        ),
      );
      final container = await boot(tester, storage: storage);
      await tester.tap(find.text('検索を開始する'));
      await tester.pumpAndSettle();
      await answerQuestions(tester);
      final baseline = container.read(searchDraftProvider);
      await enterDetails(tester, mode: 'either');
      await tester.tap(find.text('1泊2日'));
      await reveal(tester, find.byKey(const ValueKey('total-budget')));
      await tester.drag(
        find.byKey(const ValueKey('total-budget')),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('company-family')));
      await tester.tap(find.byKey(const ValueKey('company-family')));
      await tester.pumpAndSettle();
      expect(container.read(searchDraftProvider).company, Company.family);
      await tester.tap(find.text('この条件を保存'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '編集した条件');
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      expect(
        container
            .read(settingsProvider)
            .requireValue
            .presets
            .single
            .conditions
            .company,
        Company.family,
      );
      expect(container.read(settingsProvider).requireValue.lastSearch, isNull);
      final before = DateTime.now().toUtc();
      await tester.tap(find.text('詳細設定をスキップ'));
      await tester.pumpAndSettle();
      final last = container.read(settingsProvider).requireValue.lastSearch!;
      expect(last.conditions.origin, '小樽駅');
      expect(last.conditions.transport, TravelMode.either);
      expect(last.conditions.budget, baseline.budget);
      expect(last.conditions.company, baseline.company);
      expect(last.conditions.walking, baseline.walking);
      expect(last.conditions.length, baseline.length);
      expect(last.searchedAt.isUtc, isTrue);
      expect(last.searchedAt.isBefore(before), isFalse);
      expect(last.toJson()['searchedAt'], endsWith('Z'));
      expect(container.read(tripProvider).travelDate, isNull);
      final d = container.read(discoveryProvider);
      expect(d.step, 3);
      final expected = RecommendationService().recommend('食', [
        0,
        0,
      ], filters: last.conditions);
      expect(d.deck.map((e) => e.id), expected.map((e) => e.id));
      expect(
        container.read(settingsProvider).requireValue.profile.budget,
        25000,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'preset details are skip defaults and saving failure does not execute search',
    (tester) async {
      final storage = MemorySettingsStorage();
      const preset = SearchConditions(
        origin: '千歳駅',
        budget: 23000,
        maxMinutes: 300,
        company: Company.couple,
        walking: Walking.light,
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
      expect(find.byKey(const ValueKey('mood-0')), findsOneWidget);
      await answerQuestions(tester);
      expect(container.read(searchDraftProvider).toJson(), preset.toJson());
      await tester.tap(find.text('この出発地にする'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('travel-transit')));
      await tester.pumpAndSettle();
      storage.failWrite = true;
      await tester.tap(find.text('詳細設定をスキップ'));
      await tester.pumpAndSettle();
      expect(container.read(discoveryProvider).step, 1);
      expect(container.read(settingsProvider).requireValue.lastSearch, isNull);
      expect(find.textContaining('検索条件を保存できませんでした'), findsOneWidget);
      storage.failWrite = false;
      await tester.tap(find.text('詳細設定をスキップ'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(settingsProvider)
            .requireValue
            .lastSearch!
            .conditions
            .maxMinutes,
        300,
      );
      expect(
        container
            .read(settingsProvider)
            .requireValue
            .presets
            .single
            .conditions
            .toJson(),
        preset.toJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets(
      'small Android layout and keyboard at $size',
      (tester) async {
        final container = await boot(tester);
        await tester.binding.setSurfaceSize(size);
        await tester.tap(find.text('検索を開始する'));
        await tester.pumpAndSettle();
        await answerQuestions(tester);
        await tester.tap(find.byKey(const ValueKey('search-origin')));
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(find.text('この出発地にする').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text('この出発地にする'));
        await tester.pumpAndSettle();
        await reveal(tester, find.byKey(const ValueKey('travel-either')));
        await tester.tap(find.byKey(const ValueKey('travel-either')));
        await tester.pumpAndSettle();
        expect(find.text('この条件で探す').hitTestable(), findsOneWidget);
        expect(find.text('詳細設定をスキップ').hitTestable(), findsOneWidget);
        expect(find.byType(CalendarDatePicker), findsNothing);
        expect(container.read(conditionsStepProvider), 2);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({TargetPlatform.android}),
    );
  }
}
