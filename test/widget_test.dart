import 'package:sightseeing_matching_app/widgets/departure_map.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/main.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/repository/settings_repository.dart';
import 'package:sightseeing_matching_app/state/settings_state.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:sightseeing_matching_app/state/experience_photos.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'package:sightseeing_matching_app/service/curiosity_questions.dart';
import 'test_support.dart';

Future<void> reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(finder), alignment: .2);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> boot(
  WidgetTester tester, {
  MemorySettingsStorage? storage,
  Future<Map<String, ImageInfo?>> Function()? photos,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      mapTilesEnabledProvider.overrideWithValue(false),
      settingsRepositoryProvider.overrideWithValue(
        LocalSettingsRepository(storage: storage ?? MemorySettingsStorage()),
      ),
      experiencePhotosProvider.overrideWith(
        (ref) => photos?.call() ?? Future.value({}),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MyApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> answerQuestions(
  WidgetTester tester, {
  int mood = 0,
  int reason = 0,
  int broaden = 0,
}) async {
  await tester.tap(find.byKey(ValueKey('mood-$mood')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(CuriosityQuestions.reason(mood).choices[reason]));
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(CuriosityQuestions.broaden(mood, reason).choices[broaden]),
  );
  await tester.pumpAndSettle();
}

Future<void> enterDetails(
  WidgetTester tester, {
  String origin = '小樽駅',
  String mode = 'car',
  String length = 'day',
  String company = 'solo',
}) async {
  await tester.tap(find.byKey(ValueKey('origin-chip-$origin')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('travel-$mode')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('length-$length')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('company-$company')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'questions precede conditions; execution, cards and itinerary remain connected',
    (tester) async {
      final container = await boot(tester);
      expect(find.text('前回の条件で探す'), findsNothing);
      await tester.tap(find.text('検索を開始する'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mood-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mood-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('地元の人しか知らない、秘密の味'));
      await tester.pumpAndSettle();
      expect(find.text('秘密の味から、もう一歩。'), findsOneWidget);
      await tester.tap(find.byTooltip('前の画面へ'));
      await tester.pumpAndSettle();
      expect(container.read(discoveryProvider).answers, [1]);
      await tester.tap(find.text('誰もが知る、とびきりおいしいもの'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作り手のこだわりを知ってみたい'));
      await tester.pumpAndSettle();
      expect(find.text('どこから旅を始める？'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(container.read(settingsProvider).requireValue.lastSearch, isNull);
      await enterDetails(tester, length: 'overnight');
      await tester.pumpAndSettle();
      await tester.tap(find.text('この条件で探す'));
      await tester.pumpAndSettle();
      final last = container.read(settingsProvider).requireValue.lastSearch!;
      expect(last.conditions.origin, '小樽駅');
      expect(last.conditions.transport, TravelMode.car);
      expect(last.conditions.length, TripLength.overnight);
      expect(last.searchedAt.isUtc, isTrue);
      expect(container.read(tripProvider).travelDate, isNull);
      final initial = container.read(discoveryProvider).deck;
      await tester.drag(find.byType(Dismissible), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider).saved, isEmpty);
      await tester.drag(find.byType(Dismissible), const Offset(350, 0));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider).saved.single.id, initial[1].id);
      await tester.longPress(find.text(initial[2].title));
      await tester.pumpAndSettle();
      expect(find.text('もう一歩、奥へ。'), findsOneWidget);
      await reveal(tester, find.text('この体験を保存'));
      await tester.tap(find.text('この体験を保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('旅行計画へ'));
      await tester.pumpAndSettle();
      expect(find.text('出発地：小樽駅 · 移動：車'), findsOneWidget);
      expect(find.text('旅行日を選択（未確定）'), findsOneWidget);
      final before = container.read(tripProvider).stops.first.id;
      await reveal(tester, find.byType(ReorderableDragStartListener).first);
      await tester.drag(
        find.byType(ReorderableDragStartListener).first,
        const Offset(0, 220),
      );
      await tester.pumpAndSettle();
      expect(container.read(tripProvider).stops.first.id, isNot(before));
      await reveal(tester, find.text('自分で組み立てる'));
      await tester.tap(find.text('自分で組み立てる'));
      await tester.pumpAndSettle();
      expect(find.text('マイプラン'), findsOneWidget);
      expect(find.textContaining('サンプル時刻・実際の運行情報ではありません'), findsOneWidget);
      expect(find.textContaining('旅行日未確定'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('AIに提案してもらう'));
      await tester.tap(find.text('AIに提案してもらう'));
      await tester.pumpAndSettle();
      expect(find.text('デモ用の旅程'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('旅を組み立てる'));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider).stops.length, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'profile and preset management remain independent of the search flow',
    (tester) async {
      final storage = MemorySettingsStorage();
      final container = await boot(tester, storage: storage);
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '旭川駅');
      await reveal(tester, find.text('基本設定を保存'));
      await tester.tap(find.text('基本設定を保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('発見する'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('検索を開始する'));
      await tester.pumpAndSettle();
      await answerQuestions(tester);
      expect(container.read(searchDraftProvider).origin, '旭川駅');
      await enterDetails(tester);
      await tester.tap(find.text('条件を保存して検索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '小樽の休日');
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      await container
          .read(settingsProvider.notifier)
          .savePreset(const SearchConditions(origin: '千歳駅'), 'もう一つ');
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('名前の変更').first);
      await tester.tap(find.text('名前の変更').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '名前を変更');
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      final card = find.ancestor(
        of: find.text('名前を変更'),
        matching: find.byType(Card),
      );
      await reveal(
        tester,
        find.descendant(of: card, matching: find.text('内容の編集')),
      );
      await tester.tap(find.descendant(of: card, matching: find.text('内容の編集')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '江別駅');
      await reveal(tester, find.text('上書き保存'));
      await tester.tap(find.text('上書き保存'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('名前を変更'));
      await tester.tap(find.descendant(of: card, matching: find.text('読み込み')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mood-0')), findsOneWidget);
      await answerQuestions(tester);
      expect(container.read(searchDraftProvider).origin, '江別駅');
      expect(
        container.read(settingsProvider).requireValue.profile.origin,
        '旭川駅',
      );
      expect(
        container
            .read(settingsProvider)
            .requireValue
            .lastSearch!
            .conditions
            .origin,
        '小樽駅',
      );
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.descendant(of: card, matching: find.text('削除')),
      );
      await tester.tap(find.descendant(of: card, matching: find.text('削除')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).requireValue.presets.length, 2);
      await tester.tap(find.descendant(of: card, matching: find.text('削除')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '削除'));
      await tester.pumpAndSettle();
      expect(
        (await LocalSettingsRepository(storage: storage).load()).presets.length,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'LastSearch starts with new questions and legacy dates never block searching',
    (tester) async {
      final storage = MemorySettingsStorage();
      await LocalSettingsRepository(storage: storage).save(
        SavedSettings(
          profile: const UserProfile(origin: '旭川駅'),
          lastSearch: LastSearch(
            conditions: SearchConditions(
              origin: '函館駅',
              dateChoice: DateChoice.fixed,
              fixedDate: DateTime(2020),
            ),
            searchedAt: DateTime(2020),
          ),
        ),
      );
      final container = await boot(tester, storage: storage);
      await tester.tap(find.text('前回の条件で探す'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mood-0')), findsOneWidget);
      await answerQuestions(tester);
      expect(container.read(searchDraftProvider).origin, '函館駅');
      expect(find.byType(CalendarDatePicker), findsNothing);
      await tester.tap(find.text('この出発地にする'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('travel-transit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('length-day')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('company-solo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この条件で探す'));
      await tester.pumpAndSettle();
      expect(container.read(discoveryProvider).step, 3);
      expect(container.read(tripProvider).travelDate, isNull);
      container.read(discoveryProvider.notifier).reset();
      await tester.pumpAndSettle();
      await tester.tap(find.text('検索を開始する'));
      await tester.pumpAndSettle();
      await answerQuestions(tester);
      expect(container.read(searchDraftProvider).origin, '旭川駅');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('all six moods and question branches remain intact', (
    tester,
  ) async {
    final container = await boot(tester);
    await tester.binding.setSurfaceSize(const Size(360, 640));
    final flow = container.read(discoveryProvider.notifier);
    for (var i = 0; i < 6; i++) {
      flow.startQuestions();
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('mood-$i')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('mood-$i')));
      await tester.pumpAndSettle();
      expect(find.text(CuriosityQuestions.reason(i).title), findsOneWidget);
      await tester.tap(find.text(CuriosityQuestions.reason(i).choices.first));
      await tester.pumpAndSettle();
      expect(find.text(CuriosityQuestions.broaden(i, 0).title), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'photos are prepared once and unchanged horizontal swipes save or skip',
    (tester) async {
      final ready = Completer<Map<String, ImageInfo?>>();
      var loads = 0;
      final container = await boot(
        tester,
        photos: () {
          loads++;
          return ready.future;
        },
      );
      final flow = container.read(discoveryProvider.notifier);
      flow.startQuestions();
      flow.selectMood(0);
      flow.answer(0);
      flow.answer(0);
      flow.showExplore();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      ready.complete({});
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(Dismissible), const Offset(-350, 0));
        await tester.pumpAndSettle();
      }
      expect(container.read(discoveryProvider).index, 0);
      await tester.drag(find.byType(Dismissible), const Offset(350, 0));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider).saved.length, 1);
      expect(loads, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('load and save failures keep profile data and editable input', (
    tester,
  ) async {
    final storage = MemorySettingsStorage()..failRead = true;
    await boot(tester, storage: storage);
    expect(find.text('再読み込み'), findsOneWidget);
    storage.failRead = false;
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('プロフィール'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '入力は残す');
    await reveal(tester, find.text('基本設定を保存'));
    storage.failWrite = true;
    await tester.tap(find.text('基本設定を保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存できませんでした'), findsOneWidget);
    storage.failWrite = false;
    await tester.tap(find.text('基本設定を保存'));
    await tester.pumpAndSettle();
    expect(
      (await LocalSettingsRepository(storage: storage).load()).profile.origin,
      '入力は残す',
    );
    expect(tester.takeException(), isNull);
  });
}
