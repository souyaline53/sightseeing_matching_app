import 'package:sightseeing_matching_app/screen/itinerary/widgets/itinerary_transport_sheet.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'package:sightseeing_matching_app/screen/shared/trips/trips_drawer.dart';
import 'package:sightseeing_matching_app/screen/bookmark/widgets/bookmark_timeline.dart';
import 'package:sightseeing_matching_app/screen/bookmark/widgets/booklet_illustration.dart';
import 'package:sightseeing_matching_app/screen/shared/experiences/experience_detail.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot, reveal;

void main() {
  initializeCatalogTests();
  testWidgets(
    'empty booklet shows illustration and creation entry without recommendations',
    (tester) async {
      final container = await boot(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('旅のしおり'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BookletIllustration), findsOneWidget);
      expect(find.text('おすすめの体験'), findsNothing);
      expect(find.byType(ExperienceDetail), findsNothing);
      expect(container.read(tripLibraryProvider).requireValue.plans, isEmpty);
      await reveal(tester, find.text('Step1. 興味から旅行を作る'));
      await tester.tap(find.text('Step1. 興味から旅行を作る'));
      await tester.pumpAndSettle();
      expect(container.read(discoveryProvider).question, 0);
      expect(container.read(tripLibraryProvider).requireValue.plans, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty home drawer and new search do not create saved plans', (
    tester,
  ) async {
    final container = await boot(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('旅のしおり'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('まだ旅のしおりが\nありません'), findsOneWidget);
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
      expect(find.text('2020年1月1日'), findsNWidgets(2));
      expect(find.byType(BookmarkTimeline), findsOneWidget);
      expect(find.text('旅のしおりを開く'), findsNothing);
      await reveal(tester, find.byKey(const ValueKey('bookmark-stop-3')));
      expect(
        find.byKey(const ValueKey('bookmark-stop-3')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('旅の一覧を開く'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作りかけの旅'));
      await tester.pumpAndSettle();
      expect(
        container.read(tripLibraryProvider).requireValue.activeId,
        draft.id,
      );
      expect(find.byKey(const ValueKey('home-trip-hero')), findsNothing);
      expect(find.text('保存した観光地から旅を作る'), findsOneWidget);
      await tester.tap(find.text('保存した観光地から旅を作る'));
      await tester.pumpAndSettle();
      final spot = find.byKey(ValueKey('setup-spot-${experiences.first.id}'));
      await reveal(tester, spot);
      await tester.tap(spot);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('setup-create-manual')));
      await tester.pumpAndSettle();
      expect(find.byType(ItineraryEditor), findsOneWidget);
      expect(container.read(tripProvider).id, isNot(draft.id));
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
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('旅のしおり'),
      ),
    );
    await tester.pumpAndSettle();
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
    expect(find.text('まだ旅のしおりが\nありません'), findsOneWidget);
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
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('旅のしおり'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(const Size(320, 568));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Step1. 興味から旅行を作る'));
      expect(find.text('Step1. 興味から旅行を作る').hitTestable(), findsOneWidget);
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
    'saved transport details expand inline and remain collapsed when switching trips',
    (tester) async {
      final storage = MemorySettingsStorage();
      final trip = TripState(
        id: 'with-transport',
        stops: [experiences.first],
        transportSelections: [
          TransportSelection({
            'fromSpotId': TripState.departureEndpointId('札幌駅'),
            'toSpotId': experiences.first.id,
            'selectedTripId': 'saved-service',
            'boardingStopName': '札幌の乗車駅',
            'alightingStopName': '夕張の降車駅',
            'departureMinutes': 480,
            'arrivalMinutes': 540,
          }),
        ],
      );
      final other = TripState(id: 'another-trip', stops: [experiences[1]]);
      await LocalTripsRepository(
        storage: storage,
      ).save(TripLibrary(plans: [trip, other], activeId: trip.id));
      final container = await boot(tester, tripStorage: storage);
      final row = find.byKey(const ValueKey('saved-transport-saved-service'));
      await reveal(tester, row);
      expect(find.textContaining('札幌の乗車駅'), findsNothing);
      await tester.tap(
        find.descendant(of: row, matching: find.byType(ListTile)).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('札幌の乗車駅'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(
        find.descendant(of: row, matching: find.byType(ListTile)).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('札幌の乗車駅'), findsNothing);
      container.read(tripLibraryProvider.notifier).select(other.id);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('saved-transport-saved-service')),
        findsNothing,
      );
      expect(find.text('交通を選ぶ'), findsWidgets);
      final missing = find.byType(ExpansionTile).first;
      await reveal(tester, missing);
      await tester.tap(missing);
      await tester.pumpAndSettle();
      final choose = find.text('交通を選択');
      await reveal(tester, choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(find.byType(ItineraryEditor), findsOneWidget);
      expect(container.read(tripProvider).id, other.id);
      final sheet = tester.widget<ItineraryTransportSheet>(
        find.byType(ItineraryTransportSheet),
      );
      expect(sheet.from?.id, other.originEndpointId);
      expect(sheet.to?.id, experiences[1].id);
      expect(sheet.collapsed, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inline timeline reaches every stop, details and editor without another page',
    (tester) async {
      final storage = MemorySettingsStorage();
      final trip = TripState(title: '全スポットを巡る旅', stops: experiences);
      await LocalTripsRepository(
        storage: storage,
      ).save(TripLibrary(plans: [trip]));
      final container = await boot(tester, tripStorage: storage);
      expect(find.byType(BookmarkTimeline), findsOneWidget);
      expect(find.text('旅のしおりを開く'), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      final first = find.byKey(const ValueKey('bookmark-stop-0'));
      await reveal(tester, first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ExperienceDetail>(find.byType(ExperienceDetail))
            .experience
            .id,
        experiences.first.id,
      );
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      final last = find.byKey(const ValueKey('bookmark-stop-9'));
      await reveal(tester, last);
      expect(last.hitTestable(), findsOneWidget);
      final button = find.byKey(const ValueKey('bookmark-edit'));
      await reveal(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(ItineraryEditor), findsOneWidget);
      expect(container.read(tripProvider).id, trip.id);
      expect(tester.takeException(), isNull);
    },
  );

  for (final hasTrip in [true, false]) {
    for (final size in [const Size(390, 844), const Size(320, 568)]) {
      testWidgets(
        'booklet remains usable with enlarged text at $size: trip=$hasTrip',
        (tester) async {
          final storage = MemorySettingsStorage();
          if (hasTrip) {
            await LocalTripsRepository(storage: storage).save(
              TripLibrary(
                plans: [
                  TripState(
                    title: '少し長い旅のタイトルでも気持ちよく読めるしおり',
                    stops: experiences.take(3).toList(),
                  ),
                ],
              ),
            );
          }
          await boot(tester, tripStorage: storage);
          if (!hasTrip) {
            await tester.tap(
              find.descendant(
                of: find.byType(NavigationBar),
                matching: find.text('旅のしおり'),
              ),
            );
          }
          await tester.binding.setSurfaceSize(size);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final button = hasTrip
              ? find.byKey(const ValueKey('bookmark-edit'))
              : find.text('Step1. 興味から旅行を作る');
          await reveal(tester, button);
          expect(button.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
