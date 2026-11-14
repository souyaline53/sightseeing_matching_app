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
    'missing transit access blocks both buttons only in transit mode',
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
      container.read(itinerarySetupProvider.notifier).toggle(spot.id);
      await tester.pump();
      await tester.pumpAndSettle();
      for (final mode in [
        TravelMode.transit,
        TravelMode.car,
        TravelMode.either,
      ]) {
        final setup = container.read(itinerarySetupProvider);
        container
            .read(itinerarySetupProvider.notifier)
            .update(
              setup.copyWith(
                conditions: setup.conditions.copyWith(transport: mode),
              ),
            );
        await tester.pumpAndSettle();
        expect(
          tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('setup-create-manual')),
                  )
                  .onPressed ==
              null,
          mode == TravelMode.transit,
        );
        expect(
          tester
                  .widget<OutlinedButton>(
                    find.byKey(const ValueKey('setup-create-ai')),
                  )
                  .onPressed ==
              null,
          mode == TravelMode.transit,
        );
      }
      final warning = tester.widget<Text>(find.text('公共交通では行けません'));
      expect(warning.style?.color, Colors.red);
      for (final day in [16, 17]) {
        final setup = container.read(itinerarySetupProvider);
        container
            .read(itinerarySetupProvider.notifier)
            .update(
              setup.copyWith(
                conditions: setup.conditions.copyWith(
                  dateChoice: DateChoice.fixed,
                  fixedDate: DateTime(2026, 11, day),
                ),
              ),
            );
        await tester.pumpAndSettle();
        expect(
          tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('setup-create-manual')),
                  )
                  .onPressed ==
              null,
          day == 16,
        );
        expect(
          tester
                  .widget<OutlinedButton>(
                    find.byKey(const ValueKey('setup-create-ai')),
                  )
                  .onPressed ==
              null,
          day == 16,
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
    },
  );
}
