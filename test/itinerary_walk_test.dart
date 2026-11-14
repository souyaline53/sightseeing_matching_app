import 'package:sightseeing_matching_app/screen/bookmark/bookmark_home.dart';
import 'package:sightseeing_matching_app/state/app_tab.dart';
import 'departure_fixtures.dart';
import 'package:sightseeing_matching_app/data/departure_places.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/model/transport_journey.dart';
import 'package:sightseeing_matching_app/model/travel_catalog.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/repository/transport_journey_repository.dart';
import 'package:sightseeing_matching_app/repository/transport_repository.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_editor.dart';
import 'package:sightseeing_matching_app/service/transport/itinerary_transport_options.dart';
import 'package:sightseeing_matching_app/state/experience_photos.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/widgets/departure_map.dart';
import 'test_support.dart';

void main() {
  test(
    'shared stop identity is exact, multiple choices are supported and names alone do not match',
    () {
      List<AccessStop> stops(List<String> ids) =>
          ids.map((id) => AccessStop({'stopId': id})).toList();
      expect(sharesAccessStop(stops(['a', 'b']), stops(['c', 'b'])), true);
      expect(sharesAccessStop(stops(['f1~a']), stops(['f2~a'])), false);
      expect(sharesAccessStop([], []), false);
      expect(sharesAccessStop(stops(['']), stops([''])), false);
      expect(
        sharesAccessStop([
          AccessStop({'stopId': 'a', 'isActive': false}),
        ], stops(['a'])),
        false,
      );
      final parsed = JourneySearchResult({
        'walkingOnly': true,
        'journeys': [],
        'warnings': [],
      });
      expect(parsed.walkingOnly, true);
      expect(parsed.journeys, isEmpty);
    },
  );
  test(
    'a preserved bus loop in a walking segment cannot set the following departure cutoff',
    () {
      Experience point(String id, String stop) => Experience.fromJson({
        ...const Experience('', '', '', '', '', '', '', '', 60).toJson(),
        'id': id,
        'accessStops': [
          {'stopId': stop},
        ],
      });
      final old = TransportSelection({
        'fromSpotId': 'A',
        'toSpotId': 'B',
        'arrivalMinutes': 600,
      });
      final trip = TripState(
        stops: [
          point('A', 'shared'),
          point('B', 'shared'),
          point('C', 'other'),
        ],
        transportSelections: [old],
      );
      expect(segmentEarliestDeparture(trip, 'B'), 480 * 60);
      expect(
        segmentEarliestDeparture(trip, 'B', previousWalkingOnly: true),
        480 * 60,
      );
    },
  );
  for (final exact in [true, false]) {
    testWidgets(
      '${exact ? 'shared ID' : 'cached 500m classification'} displays only walking in editor and booklet without overwriting old selection',
      (tester) async {
        Experience point(String id, String stopId) => Experience.fromJson({
          ...const Experience('', '', '', '', '', '', '', '', 60).toJson(),
          'id': id,
          'name': '観光地$id',
          'accessStops': [
            {'stopId': stopId, 'walkingMinutes': null},
          ],
        });
        final spots = [
          point('A', 'stop-a'),
          point('B', exact ? 'stop-a' : 'stop-b'),
        ];
        final old = TransportSelection({
          'fromSpotId': 'A',
          'toSpotId': 'B',
          'selectedTripId': 'old-loop',
          'boardingStopName': '共通の停留所',
          'alightingStopName': '共通の停留所',
          'departureMinutes': 480,
          'arrivalMinutes': 540,
        });
        final repo = LocalTripsRepository(storage: MemorySettingsStorage());
        await repo.save(
          TripLibrary(
            plans: [
              TripState(
                stops: spots,
                saved: spots,
                travelDate: DateTime(2026, 6, 1),
                transportSelections: [old],
              ),
            ],
          ),
        );
        var searches = 0, timetableReads = 0;
        final container = ProviderContainer(
          overrides: [
            departurePlacesProvider.overrideWith(
              (ref) => Stream.value(departurePlaces),
            ),
            tripsRepositoryProvider.overrideWithValue(repo),
            catalogProvider.overrideWith(
              (ref) => Stream.value(TravelCatalog(experiences: spots)),
            ),
            journeySearchProvider.overrideWithValue((query) async {
              searches++;
              return JourneySearchResult({
                'walkingOnly': true,
                'journeys': [],
                'warnings': [],
              });
            }),
            transportDataProvider.overrideWith((ref, key) async {
              timetableReads++;
              return TransportData([], [], [], [], []);
            }),
            mapTilesEnabledProvider.overrideWithValue(false),
            experiencePhotosProvider.overrideWith((ref) async => {}),
          ],
        );
        addTearDown(container.dispose);
        await container.read(tripLibraryProvider.future);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: _withBooklet(const ItineraryEditor())),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('transport-sheet-header')),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('walking-only')), findsOneWidget);
        expect(find.textContaining('この区間は徒歩のみ'), findsOneWidget);
        expect(find.textContaining('この便で行く'), findsNothing);
        expect(find.textContaining('候補がありません'), findsNothing);
        expect(find.textContaining('保存した便は'), findsNothing);
        expect(searches, exact ? 0 : 1);
        expect(timetableReads, exact ? 0 : 1);
        await tester.tap(find.byKey(const ValueKey('itinerary-view-booklet')));
        await tester.pumpAndSettle();
        final walking = find.text('徒歩で移動');
        await tester.ensureVisible(walking);
        await tester.pumpAndSettle();
        expect(walking, findsOneWidget);
        expect(
          find.byKey(const ValueKey('saved-transport-old-loop')),
          findsNothing,
        );
        expect(searches, exact ? 0 : 1);
        expect(timetableReads, exact ? 0 : 1);
        expect(
          (await repo.load()).activeTrip!.transportSelections.single.toJson(),
          old.toJson(),
        );
      },
    );
  }
}

Widget _withBooklet(Widget editor) => Consumer(
  builder: (context, ref, child) => IndexedStack(
    index: ref.watch(appTabProvider) == AppTab.bookmark ? 1 : 0,
    children: [editor, const BookmarkHome()],
  ),
);
