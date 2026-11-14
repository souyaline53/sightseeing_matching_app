import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/departure_places.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/repository/settings_repository.dart';
import 'package:sightseeing_matching_app/screen/shared/discovery/search_conditions_screen.dart';
import 'package:sightseeing_matching_app/state/conditions_step_state.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:sightseeing_matching_app/state/settings_state.dart';
import 'departure_fixtures.dart';
import 'test_support.dart';

void main() {
  for (final mode in TravelMode.values) {
    testWidgets(
      '${mode.name} advances through separate transport and duration pages',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              LocalSettingsRepository(storage: MemorySettingsStorage()),
            ),
            departurePlacesProvider.overrideWith(
              (ref) => Stream.value(departurePlaces),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);
        final discovery = container.read(discoveryProvider.notifier);
        discovery.selectMood(0);
        discovery.answer(0);
        discovery.answer(0);
        discovery.showConditions();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: SearchConditionsScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Q4 / 8'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('origin-chip-札幌駅')));
        await tester.pumpAndSettle();
        expect(find.text('Q5 / 8'), findsOneWidget);
        expect(find.byKey(const ValueKey('length-day')), findsNothing);
        await tester.tap(find.byKey(ValueKey('travel-${mode.name}')));
        await tester.pumpAndSettle();
        expect(find.text('Q6 / 8'), findsOneWidget);
        expect(find.byKey(ValueKey('travel-${mode.name}')), findsNothing);
        expect(container.read(searchDraftProvider).transport, mode);
        await tester.tap(find.byKey(const ValueKey('length-day')));
        await tester.pumpAndSettle();
        expect(find.text('Q7 / 8'), findsOneWidget);
        final date = DateTime.now().add(const Duration(days: 1));
        tester
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .onDateChanged(date);
        await tester.pumpAndSettle();
        expect(find.text('Q8 / 8'), findsOneWidget);
        expect(find.text('この条件で探す'), findsOneWidget);
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
        }
        expect(container.read(conditionsStepProvider), 1);
        expect(container.read(searchDraftProvider).transport, mode);
        expect(container.read(searchDraftProvider).length, TripLength.day);
        expect(find.text('Q5 / 8'), findsOneWidget);
      },
    );
  }
}
