import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_setup_screen.dart';
import 'package:sightseeing_matching_app/state/itinerary_setup_state.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'test_support.dart';

void main() {
  initializeCatalogTests();

  testWidgets(
    'unavailable spots cannot be checked and changing conditions clears selections',
    (tester) async {
      final spot = Experience.fromJson({
        ...experiences.first.toJson(),
        'id': 'unregistered-spot',
        'accessStops': [],
        'visitInfo': {
          'openingHoursStatus': 'scheduled',
          'openingHours': {
            'mon': [],
            'tue': [
              {'open': '09:00', 'close': '17:00'},
            ],
          },
        },
      });
      final container = ProviderContainer(
        overrides: [
          catalogProvider.overrideWith((ref) => Stream.value(testCatalog)),
          savedExperiencesProvider.overrideWithValue([spot]),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ItinerarySetupScreen()),
        ),
      );
      final tileFinder = find.byKey(ValueKey('setup-spot-${spot.id}'));
      for (final mode in TravelMode.values) {
        for (final day in [17, 16, 17]) {
          final setup = container.read(itinerarySetupProvider);
          container
              .read(itinerarySetupProvider.notifier)
              .update(
                setup.copyWith(
                  conditions: setup.conditions.copyWith(
                    transport: mode,
                    dateChoice: DateChoice.fixed,
                    fixedDate: DateTime(2026, 11, day),
                  ),
                ),
              );
          await tester.pumpAndSettle();
          final selectable = mode != TravelMode.transit && day == 17;
          var tile = tester.widget<CheckboxListTile>(tileFinder);
          expect(tile.enabled, selectable);
          expect(tile.onChanged == null, !selectable);
          if (selectable && !tile.value!) {
            await tester.ensureVisible(tileFinder);
            await tester.tap(tileFinder);
            await tester.pumpAndSettle();
          }
          tile = tester.widget<CheckboxListTile>(tileFinder);
          expect(tile.value, selectable);
          expect(
            container
                .read(itinerarySetupProvider)
                .selectedIds
                .contains(spot.id),
            selectable,
          );
          expect(
            tester
                    .widget<FilledButton>(
                      find.byKey(const ValueKey('setup-create-manual')),
                    )
                    .onPressed ==
                null,
            !selectable,
          );
          expect(
            tester
                    .widget<OutlinedButton>(
                      find.byKey(const ValueKey('setup-create-ai')),
                    )
                    .onPressed ==
                null,
            !selectable,
          );
          final closedWarning = find.text('選択した日は定休日です');
          if (day == 16) {
            expect(tester.widget<Text>(closedWarning).style?.color, Colors.red);
            expect(
              tester.getTopLeft(closedWarning).dy,
              greaterThan(tester.getTopLeft(find.text('公共交通では行けません')).dy),
            );
          } else {
            expect(closedWarning, findsNothing);
          }
        }
      }
      // Switching back to public transit clears an existing car selection.
      final setup = container.read(itinerarySetupProvider);
      container
          .read(itinerarySetupProvider.notifier)
          .update(
            setup.copyWith(
              conditions: setup.conditions.copyWith(
                transport: TravelMode.transit,
              ),
            ),
          );
      await tester.pumpAndSettle();
      expect(container.read(itinerarySetupProvider).selectedIds, isEmpty);
      expect(tester.widget<CheckboxListTile>(tileFinder).value, isFalse);
      expect(
        tester.widget<Text>(find.text('公共交通では行けません')).style?.color,
        Colors.red,
      );
    },
  );
}
