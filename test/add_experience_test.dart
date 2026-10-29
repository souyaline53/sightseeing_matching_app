import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/mock_data.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/screen/recommendation/experience_deck.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot, reveal;

Future<void> showCoal(WidgetTester tester) async {
  final scope = ProviderScope.containerOf(
    tester.element(find.byType(ExperienceDeck)),
  );
  final deck = scope.read(discoveryProvider).deck;
  scope
      .read(discoveryProvider.notifier)
      .goTo(deck.indexWhere((e) => e.id == 'coal'));
  await tester.pumpAndSettle();
}

void main() {
  for (final fromBooklet in [false, true]) {
    testWidgets(
      'add cards to existing trip from ${fromBooklet ? 'booklet FAB' : 'itinerary button'}',
      (tester) async {
        final storage = MemorySettingsStorage();
        final trip = TripState(
          id: 'selected',
          title: '元の旅程',
          conditions: const SearchConditions(origin: '小樽駅'),
          travelDate: DateTime(2030, 4, 10),
          saved: [experiences[0]],
          stops: [experiences[0]],
        );
        final other = TripState(id: 'other', title: '別の旅程');
        await LocalTripsRepository(
          storage: storage,
        ).save(TripLibrary(plans: [other, trip], activeId: trip.id));
        final container = await boot(tester, tripStorage: storage);
        final originalSearch = container.read(discoveryProvider);
        if (fromBooklet) {
          await reveal(tester, find.text('旅のしおりを開く'));
          await tester.tap(find.text('旅のしおりを開く'));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(FloatingActionButton));
        } else {
          await tester.tap(find.text('旅を組み立てる'));
          await tester.pumpAndSettle();
        }
        await tester.pumpAndSettle();
        expect(find.text('旅を組み立てよう！'), findsOneWidget);
        final button = find.widgetWithText(OutlinedButton, '体験を追加する');
        await reveal(tester, button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(ExperienceDeck), findsOneWidget);
        await showCoal(tester);
        if (fromBooklet) {
          await tester.tap(find.byTooltip('体験を保存').hitTestable());
        } else {
          await tester.drag(
            find.byType(Dismissible).first,
            const Offset(0, -500),
          );
        }
        await tester.pumpAndSettle();
        final edited = container.read(tripProvider);
        expect(edited.id, trip.id);
        expect(edited.stops.map((e) => e.id), ['melon', 'coal']);
        expect(edited.origin, '小樽駅');
        expect(edited.travelDate, DateTime(2030, 4, 10));
        expect(container.read(discoveryProvider), same(originalSearch));
        final library = container.read(tripLibraryProvider).requireValue;
        expect(library.plans, hasLength(2));
        expect(
          library.plans.firstWhere((p) => p.id == other.id).toJson(),
          other.toJson(),
        );
        await tester.tap(find.text('旅程に戻る（2件）'));
        await tester.pumpAndSettle();
        expect(find.text('旅を組み立てよう！'), findsOneWidget);
        await container.read(tripLibraryProvider.notifier).retrySave();
        expect(
          (await LocalTripsRepository(
            storage: storage,
          ).load()).activeTrip!.stops,
          hasLength(2),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'add button also opens cards after restart with no question answers or saved trip',
    (tester) async {
      final container = await boot(tester);
      await tester.tap(find.text('旅を組み立てる'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(OutlinedButton, '体験を追加する');
      await reveal(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await showCoal(tester);
      expect(container.read(tripLibraryProvider).requireValue.plans, isEmpty);
      await tester.tap(find.byTooltip('体験を保存').hitTestable());
      await tester.pumpAndSettle();
      expect(
        container.read(tripLibraryProvider).requireValue.plans,
        hasLength(1),
      );
      expect(container.read(tripProvider).stops.single.id, 'coal');
      expect(container.read(discoveryProvider).step, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
