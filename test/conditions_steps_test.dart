import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/repository/settings_repository.dart';
import 'package:sightseeing_matching_app/state/conditions_step_state.dart';
import 'package:sightseeing_matching_app/state/settings_state.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot, reveal;

void main() {
  testWidgets(
    'three steps keep all values, support back, save and hand off to questions',
    (tester) async {
      final storage = MemorySettingsStorage();
      final container = await boot(tester, storage: storage);
      await tester.tap(find.text('検索を開始する'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 1/3'), findsOneWidget);
      expect(find.text('どこから、どうやって行く？'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('search-origin')),
        '江別駅',
      );
      await tester.tap(find.byKey(const ValueKey('travel-either')));
      await reveal(tester, find.byKey(const ValueKey('travel-time')));
      await tester.drag(
        find.byKey(const ValueKey('travel-time')),
        const Offset(80, 0),
      );
      await tester.pumpAndSettle();
      final minutes = container.read(searchDraftProvider).maxMinutes;
      expect(minutes, inInclusiveRange(30, 240));
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 2/3'), findsOneWidget);
      expect(find.byType(CalendarDatePicker), findsNothing);
      await tester.tap(find.text('日付指定'));
      await tester.pumpAndSettle();
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(calendar.firstDate, DateUtils.dateOnly(DateTime.now()));
      await tester.tap(
        find
            .descendant(
              of: find.byType(CalendarDatePicker),
              matching: find.text('${DateTime.now().day}'),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(
        container.read(searchDraftProvider).fixedDate,
        DateUtils.dateOnly(DateTime.now()),
      );
      await tester.tap(find.text('次の週末'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsNothing);
      await tester.tap(find.text('2泊3日以上'));
      await reveal(tester, find.byKey(const ValueKey('total-budget')));
      await tester.drag(
        find.byKey(const ValueKey('total-budget')),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();
      final budget = container.read(searchDraftProvider).budget;
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 3/3'), findsOneWidget);
      final solo = tester.getRect(find.byKey(const ValueKey('company-solo')));
      final friends = tester.getRect(
        find.byKey(const ValueKey('company-friends')),
      );
      final couple = tester.getRect(
        find.byKey(const ValueKey('company-couple')),
      );
      final family = tester.getRect(
        find.byKey(const ValueKey('company-family')),
      );
      expect(solo.top, friends.top);
      expect(couple.top, family.top);
      expect(couple.top, greaterThan(solo.bottom));
      await tester.tap(find.byKey(const ValueKey('company-family')));
      await tester.pumpAndSettle();
      expect(find.text('少なめ').hitTestable(), findsNothing);
      await reveal(tester, find.text('さらに細かく設定'));
      await tester.tap(find.text('さらに細かく設定'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('少なめ'));
      await tester.tap(find.text('少なめ'));
      await tester.pumpAndSettle();
      final entered = container.read(searchDraftProvider);
      expect(entered.origin, '江別駅');
      expect(entered.transport, TravelMode.either);
      expect(entered.length, TripLength.longer);
      expect(entered.walking, Walking.light);
      expect(entered.company, Company.family);
      expect(entered.dateChoice, DateChoice.weekend);
      expect(entered.maxMinutes, minutes);
      expect(entered.budget, budget);
      await tester.tap(find.text('この条件を保存'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '三段階の旅');
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      final saved = await LocalSettingsRepository(storage: storage).load();
      expect(saved.presets.single.conditions.toJson(), entered.toJson());
      expect(saved.profile.origin, '札幌駅');
      expect(saved.lastSearch, isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('STEP 2/3'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('STEP 1/3'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('search-origin')))
            .controller!
            .text,
        '江別駅',
      );
      expect(container.read(searchDraftProvider).toJson(), entered.toJson());
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('次へ：好奇心を探す'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mood-0')), findsOneWidget);
      expect(container.read(searchDraftProvider).toJson(), entered.toJson());
      await tester.tap(find.byTooltip('前の画面へ'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 3/3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loaded presets retain fields and legacy travel limits need explicit correction',
    (tester) async {
      final storage = MemorySettingsStorage();
      const original = SearchConditions(
        origin: '千歳駅',
        maxMinutes: 300,
        budget: 23000,
        transport: TravelMode.car,
        length: TripLength.overnight,
        walking: Walking.plenty,
        company: Company.couple,
      );
      await LocalSettingsRepository(storage: storage).save(
        SavedSettings(
          presets: const [
            SearchPreset(id: 'legacy', name: '以前の条件', conditions: original),
          ],
        ),
      );
      final container = await boot(tester, storage: storage);
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('読み込み'));
      await tester.tap(find.text('読み込み'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 1/3'), findsOneWidget);
      expect(container.read(searchDraftProvider).toJson(), original.toJson());
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
      expect(container.read(conditionsStepProvider), 0);
      await reveal(tester, find.byKey(const ValueKey('travel-time')));
      await tester.drag(
        find.byKey(const ValueKey('travel-time')),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 2/3'), findsOneWidget);
      expect(container.read(searchDraftProvider).budget, 23000);
      expect(
        container
            .read(settingsProvider)
            .requireValue
            .presets
            .single
            .conditions
            .maxMinutes,
        300,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets(
      'Android layout with keyboard and fixed actions at $size',
      (tester) async {
        final container = await boot(tester);
        await tester.binding.setSurfaceSize(size);
        await tester.tap(find.text('検索を開始する'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('search-origin')));
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(find.text('次へ').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text('次へ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('日付指定'));
        await tester.pumpAndSettle();
        await reveal(tester, find.byType(CalendarDatePicker));
        expect(tester.takeException(), isNull);
        await reveal(tester, find.text('明日'));
        await tester.tap(find.text('明日'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('次へ'));
        await tester.pumpAndSettle();
        expect(find.text('次へ：好奇心を探す').hitTestable(), findsOneWidget);
        expect(container.read(conditionsStepProvider), 2);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({TargetPlatform.android}),
    );
  }
}
