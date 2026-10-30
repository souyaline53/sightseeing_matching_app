import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'package:sightseeing_matching_app/screen/home/trips_drawer.dart';
import 'package:sightseeing_matching_app/screen/home/home_experience_gallery.dart';
import 'package:sightseeing_matching_app/screen/recommendation/experience_detail.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot, reveal;

void main() {
  initializeCatalogTests();
  testWidgets(
    'empty home gallery opens the matching detail sheet without creating a trip',
    (tester) async {
      final container = await boot(tester);
      expect(find.byType(HomeExperienceGallery), findsOneWidget);
      final photo = find.byKey(const ValueKey('home-gallery-melon'));
      await reveal(tester, photo);
      expect(
        tester.getRect(find.text('新しい旅を探す')).top,
        lessThan(tester.getRect(find.byType(HomeExperienceGallery)).top),
      );
      await tester.tap(photo);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        tester
            .widget<ExperienceDetail>(find.byType(ExperienceDetail))
            .experience
            .id,
        'melon',
      );
      expect(find.text(experiences.first.story), findsOneWidget);
      expect(container.read(tripLibraryProvider).requireValue.plans, isEmpty);
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      expect(find.text('まだ旅行の予定はありません'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('home-gallery-list')),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-gallery-coal')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ExperienceDetail>(find.byType(ExperienceDetail))
            .experience
            .id,
        'coal',
      );
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      container
          .read(tripLibraryProvider.notifier)
          .upsert(TripState(stops: [experiences.first]));
      await tester.pumpAndSettle();
      expect(find.byType(HomeExperienceGallery), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty home drawer and new search do not create saved plans', (
    tester,
  ) async {
    final container = await boot(tester);
    expect(find.text('まだ旅行の予定はありません'), findsOneWidget);
    await tester.tap(find.byTooltip('旅の一覧を開く'));
    await tester.pumpAndSettle();
    expect(find.text('わたしの旅'), findsOneWidget);
    expect(find.text('保存した旅はまだありません。'), findsOneWidget);
    await tester.tap(find.text('新しい旅を追加'));
    await tester.pumpAndSettle();
    expect(container.read(discoveryProvider).question, 0);
    expect(container.read(tripLibraryProvider).requireValue.plans, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected past trip, compact timeline, switching and draft editing',
    (tester) async {
      final storage = MemorySettingsStorage();
      final past = TripState(
        id: 'past',
        title: '昔の小旅行',
        travelDate: DateTime(2020),
        saved: experiences.take(4).toList(),
        stops: experiences.take(4).toList(),
      );
      final draft = TripState(id: 'draft', title: '作りかけの旅');
      await LocalTripsRepository(
        storage: storage,
      ).save(TripLibrary(plans: [draft, past], activeId: past.id));
      final container = await boot(tester, tripStorage: storage);
      expect(find.text('昔の小旅行'), findsOneWidget);
      expect(find.text('2020年1月1日'), findsOneWidget);
      await reveal(tester, find.text('すべて見る'));
      expect(find.text('旅のしおり（4スポット）'), findsOneWidget);
      await tester.tap(find.text('すべて見る'));
      await tester.pumpAndSettle();
      expect(find.text('マイプラン'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('旅の一覧を開く'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作りかけの旅'));
      await tester.pumpAndSettle();
      expect(
        container.read(tripLibraryProvider).requireValue.activeId,
        draft.id,
      );
      expect(find.text('次の旅  ·  作成中'), findsOneWidget);
      expect(find.text('日程未定'), findsOneWidget);
      expect(find.text('旅のしおりを開く').hitTestable(), findsOneWidget);
      await tester.tap(find.text('旅のしおりを開く'));
      await tester.pumpAndSettle();
      expect(find.text('旅を組み立てよう！'), findsOneWidget);
      expect(container.read(tripProvider).id, draft.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('drawer rename, duplicate and confirmed final deletion', (
    tester,
  ) async {
    final storage = MemorySettingsStorage();
    final trip = TripState(id: 'one', title: '最初の旅');
    await LocalTripsRepository(
      storage: storage,
    ).save(TripLibrary(plans: [trip], activeId: trip.id));
    final container = await boot(tester, tripStorage: storage);
    await tester.tap(find.byTooltip('旅の一覧を開く'));
    await tester.pumpAndSettle();
    Future<void> action(String label, {int row = 0}) async {
      final menu = find
          .descendant(
            of: find.byType(TripsDrawer),
            matching: find.byType(TripActionsMenu),
          )
          .at(row);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await action('名前を変更する');
    await tester.enterText(find.byType(TextField), '  ');
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();
    expect(find.text('旅行タイトルを入力してください。'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '週末の冒険');
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();
    expect(
      container.read(tripLibraryProvider).requireValue.activeTrip!.title,
      '週末の冒険',
    );
    await action('旅程を複製する');
    expect(
      container.read(tripLibraryProvider).requireValue.plans,
      hasLength(2),
    );
    await action('旅程を削除する', row: 1);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(
      container.read(tripLibraryProvider).requireValue.plans,
      hasLength(2),
    );
    await action('旅程を削除する', row: 1);
    await tester.tap(find.text('削除する'));
    await tester.pumpAndSettle();
    expect(container.read(tripLibraryProvider).requireValue.activeId, trip.id);
    await action('旅程を削除する');
    await tester.tap(find.text('削除する'));
    await tester.pumpAndSettle();
    expect(container.read(tripLibraryProvider).requireValue.plans, isEmpty);
    await tester.tap(find.byTooltip('閉じる'));
    await tester.pumpAndSettle();
    expect(find.text('まだ旅行の予定はありません'), findsOneWidget);
    await container.read(tripLibraryProvider.notifier).retrySave();
    expect(
      (await LocalTripsRepository(storage: storage).load()).activeId,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small Android drawer and draft layout remain usable',
    (tester) async {
      final storage = MemorySettingsStorage();
      final trip = TripState(title: '少し長い名前の作成途中の旅');
      await LocalTripsRepository(
        storage: storage,
      ).save(TripLibrary(plans: [trip]));
      await boot(tester, tripStorage: storage);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      await tester.pumpAndSettle();
      expect(find.text('旅のしおりを開く').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('旅の一覧を開く'));
      await tester.pumpAndSettle();
      expect(find.text('新しい旅を追加').hitTestable(), findsOneWidget);
      await tester.tapAt(const Offset(312, 280));
      await tester.pumpAndSettle();
      expect(find.byType(TripsDrawer).hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );
  testWidgets(
    'only the booklet list scrolls and every saved stop is reachable',
    (tester) async {
      final storage = MemorySettingsStorage();
      final trip = TripState(title: '全スポットを巡る旅', stops: experiences);
      await LocalTripsRepository(
        storage: storage,
      ).save(TripLibrary(plans: [trip]));
      await boot(tester, tripStorage: storage);
      final hero = find.byKey(const ValueKey('home-trip-hero'));
      final button = find.byKey(const ValueKey('home-open-booklet'));
      final heroBefore = tester.getRect(hero);
      final buttonBefore = tester.getRect(button);
      final list = find.byKey(PageStorageKey('home-stops-${trip.id}'));
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-stop-9')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      final lastRow = tester.getRect(find.byKey(const ValueKey('home-stop-9')));
      final viewport = tester.getRect(scrollable);
      expect(lastRow.top, greaterThanOrEqualTo(viewport.top - 1));
      expect(lastRow.bottom, lessThanOrEqualTo(viewport.bottom + 1));
      expect(tester.getRect(hero), heroBefore);
      expect(tester.getRect(button), buttonBefore);
      expect(button.hitTestable(), findsOneWidget);
      expect(find.text('旅のしおり（10スポット）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(390, 844), const Size(360, 740)]) {
    testWidgets('hero overlaps sheet and three stops fit at $size', (
      tester,
    ) async {
      final storage = MemorySettingsStorage();
      final trip = TripState(
        title: '夕張で見つける、新しい景色',
        stops: experiences.take(4).toList(),
      );
      await LocalTripsRepository(
        storage: storage,
      ).save(TripLibrary(plans: [trip]));
      await boot(tester, tripStorage: storage);
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
      final hero = tester.getRect(find.byKey(const ValueKey('home-trip-hero')));
      final sheet = tester.getRect(
        find.byKey(const ValueKey('home-booklet-sheet')),
      );
      expect(hero.left, 0);
      expect(hero.width, size.width);
      expect(sheet.top, closeTo(hero.bottom - 24, .1));
      final content = find.byKey(const ValueKey('home-booklet-sheet'));
      final viewport = tester.getRect(
        find.descendant(of: content, matching: find.byType(Scrollable)),
      );
      for (var i = 0; i < 3; i++) {
        final row = find.descendant(
          of: content,
          matching: find.byKey(ValueKey('home-stop-$i')),
        );
        expect(row, findsOneWidget);
        final rect = tester.getRect(row);
        expect(rect.top, greaterThanOrEqualTo(viewport.top - 1));
        expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 1));
      }
      expect(find.byKey(const ValueKey('home-stop-3')), findsOneWidget);
      expect(find.text('旅のしおり（4スポット）'), findsOneWidget);
      expect(find.text('すべて見る'), findsOneWidget);
      expect(find.text('新しい旅を探す'), findsNothing);
      expect(find.text('前回の条件で探す'), findsNothing);
      final button = tester.getRect(
        find.byKey(const ValueKey('home-open-booklet')),
      );
      final navigation = tester.getRect(find.byType(NavigationBar));
      expect(button.bottom, lessThanOrEqualTo(navigation.top));
      expect(
        find.byKey(const ValueKey('home-open-booklet')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final count in [0, 1, 2, 3]) {
    testWidgets('sheet renders exactly $count existing stops', (tester) async {
      final storage = MemorySettingsStorage();
      final trip = TripState(stops: experiences.take(count).toList());
      await LocalTripsRepository(
        storage: storage,
      ).save(TripLibrary(plans: [trip]));
      await boot(tester, tripStorage: storage);
      expect(find.text('旅のしおり（$countスポット）'), findsOneWidget);
      expect(find.text('すべて見る'), findsNothing);
      expect(
        find.text('まだスポットがありません'),
        count == 0 ? findsOneWidget : findsNothing,
      );
      for (var i = 0; i < 3; i++) {
        expect(
          find.byKey(ValueKey('home-stop-$i')),
          i < count ? findsOneWidget : findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final hasTrip in [true, false]) {
    testWidgets(
      'small screen with enlarged text scrolls without overflow: trip=$hasTrip',
      (tester) async {
        final storage = MemorySettingsStorage();
        if (hasTrip) {
          final trip = TripState(
            title: '少し長い旅のタイトルでも気持ちよく読めるしおり',
            stops: experiences.take(3).toList(),
          );
          await LocalTripsRepository(
            storage: storage,
          ).save(TripLibrary(plans: [trip]));
        }
        await boot(tester, tripStorage: storage);
        await tester.binding.setSurfaceSize(const Size(320, 568));
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button = hasTrip
            ? find.byKey(const ValueKey('home-open-booklet'))
            : find.text('新しい旅を探す');
        await reveal(tester, button);
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
