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
import 'package:sightseeing_matching_app/state/app_tab.dart';
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

void main() {
  testWidgets(
    'home, full-screen conditions, branching questions, cards and itinerary work together',
    (tester) async {
      final container = await boot(tester);
      expect(find.text('前回の条件で探す'), findsNothing);
      expect(find.text('プロフィール'), findsOneWidget);
      await tester.tap(find.text('検索を開始する'));
      await tester.pumpAndSettle();
      expect(find.text('旅行条件を設定'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.enterText(find.byType(TextField).first, '小樽駅');
      await tester.tap(find.text('車'));
      await tester.tap(find.text('1泊2日'));
      expect(container.read(settingsProvider).requireValue.lastSearch, isNull);
      await reveal(tester, find.text('次へ'));
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
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
      expect(find.text('おいしさの先に、何を知りたい？'), findsOneWidget);
      await tester.tap(find.text('作り手のこだわりを知ってみたい'));
      await tester.pumpAndSettle();
      final last = container.read(settingsProvider).requireValue.lastSearch!;
      expect(last.conditions.origin, '小樽駅');
      expect(last.conditions.transport, TravelMode.car);
      expect(last.conditions.length, TripLength.overnight);
      expect(
        container.read(settingsProvider).requireValue.profile.origin,
        '札幌駅',
      );
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
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '小樽駅',
      );
      expect(container.read(tripProvider).stops.length, 2);
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
    'profile save, multiple presets, rename edit load and confirmed deletion',
    (tester) async {
      final storage = MemorySettingsStorage();
      final container = await boot(tester, storage: storage);
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '旭川駅');
      await reveal(tester, find.text('基本設定を保存'));
      await tester.tap(find.text('基本設定を保存'));
      await tester.pumpAndSettle();
      expect(
        (await LocalSettingsRepository(storage: storage).load()).profile.origin,
        '旭川駅',
      );
      await tester.tap(find.text('発見する'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('検索を開始する'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '旭川駅',
      );
      await tester.enterText(find.byType(TextField).first, '小樽駅');
      await reveal(tester, find.text('この条件を保存'));
      await tester.tap(find.text('この条件を保存'));
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
      // Renamed preset is appended, locate its card rather than relying on list order.
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
      expect(
        container.read(settingsProvider).requireValue.profile.origin,
        '旭川駅',
      );
      expect(container.read(settingsProvider).requireValue.lastSearch, isNull);
      await reveal(tester, find.text('名前を変更'));
      await tester.tap(find.descendant(of: card, matching: find.text('読み込み')));
      await tester.pumpAndSettle();
      expect(container.read(appTabProvider), AppTab.recommendation);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '江別駅',
      );
      expect(container.read(settingsProvider).requireValue.lastSearch, isNull);
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
    'last search is reused while ordinary start uses profile and expired dates are blocked',
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
            executedAt: DateTime(2020),
          ),
        ),
      );
      final container = await boot(tester, storage: storage);
      await tester.tap(find.text('前回の条件で探す'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '函館駅',
      );
      expect(find.text('過去の日付です。旅行日を選び直してください。'), findsOneWidget);
      await reveal(tester, find.text('次へ'));
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
      expect(container.read(discoveryProvider).step, 1);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('検索を開始する'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '旭川駅',
      );
      expect(
        container.read(searchDraftProvider).dateChoice,
        DateChoice.tomorrow,
      );
      expect(
        container
            .read(settingsProvider)
            .requireValue
            .lastSearch!
            .conditions
            .origin,
        '函館駅',
      );
    },
  );

  testWidgets(
    'all moods fit on a small phone and all questions retain valid branches',
    (tester) async {
      final container = await boot(tester);
      await tester.binding.setSurfaceSize(const Size(360, 640));
      final flow = container.read(discoveryProvider.notifier);
      flow.startQuestions();
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        expect(find.byKey(ValueKey('mood-$i')).hitTestable(), findsOneWidget);
      }
      for (var i = 0; i < 6; i++) {
        flow.startQuestions();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('mood-$i')));
        await tester.pumpAndSettle();
        expect(find.text(CuriosityQuestions.reason(i).title), findsOneWidget);
        await tester.tap(find.text(CuriosityQuestions.reason(i).choices.first));
        await tester.pumpAndSettle();
        expect(
          find.text(CuriosityQuestions.broaden(i, 0).title),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'photos are prepared once and horizontal swipes save or skip without loading',
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

  testWidgets('load and save failures keep data and editable input', (
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
