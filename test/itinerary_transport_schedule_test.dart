import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/travel_catalog.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/model/transport_journey.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/repository/transport_journey_repository.dart';
import 'package:sightseeing_matching_app/repository/transport_repository.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_editor.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_spot_card.dart';
import 'package:sightseeing_matching_app/service/transport/itinerary_transport_options.dart';
import 'package:sightseeing_matching_app/state/experience_photos.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'package:sightseeing_matching_app/widgets/departure_map.dart';
import 'test_support.dart';

Experience spot(String id) => Experience.fromJson({
  ...const Experience('', '', '', '', '', '', '', '', 60).toJson(),
  'id': id,
  'name': '観光地$id',
  'accessStops': [
    {'stopId': id.toLowerCase(), 'walkingMinutes': null},
  ],
});
Json journey(String id, String from, String to, int departure, int arrival) => {
  'id': id,
  'queryDate': '2026-06-01',
  'transferCount': 0,
  'departureSeconds': departure * 60,
  'departureFromSpotSeconds': departure * 60,
  'arrivalSeconds': arrival * 60,
  'walkingMinutesBefore': null,
  'walkingMinutesAfter': null,
  'verificationStatus': 'needsReview',
  'transfers': [],
  'legs': [
    {
      'tripId': id,
      'routeId': 'route',
      'routeName': 'バス路線',
      'headsign': '目的地方面',
      'versionId': 'v1',
      'serviceDate': '2026-06-01',
      'boardingStopId': from,
      'boardingStopName': '乗車バス停',
      'boardingSequence': 1,
      'alightingStopId': to,
      'alightingStopName': '降車バス停',
      'alightingSequence': 2,
      'departureSeconds': departure * 60,
      'arrivalSeconds': arrival * 60,
    },
  ],
};
void main() {
  test(
    'departure time persists, old plans default to 08:00, previous arrivals use seconds and known destination walks',
    () {
      final initial = TripState(
        stops: [spot('A'), spot('B'), spot('C')],
        travelDate: DateTime(2026, 6, 1),
      );
      final old = initial.toJson()..remove('departureMinutes');
      expect(TripState.fromJson(old).departureMinutes, 480);
      final saved = TripState.fromJson(
        jsonDecode(jsonEncode(initial.copyWith(departureMinutes: 555).toJson()))
            as Json,
      );
      expect(saved.departureMinutes, 555);
      expect(saved.travelDate, DateTime(2026, 6, 1));
      final first = TransportJourney(
        journey('t', 'a', 'b', 480, 540),
      ).selection('A', 'B');
      final selected = initial.copyWith(transportSelections: [first]);
      expect(segmentEarliestDeparture(selected, 'B'), 32400);
      expect(segmentEarliestDeparture(selected, 'C'), 28800);
      final legacy = TransportSelection({
        'fromSpotId': 'A',
        'toSpotId': 'B',
        'serviceDate': '2026-06-01',
        'arrivalSeconds': 32401,
        'walkingMinutesAfter': 5,
      });
      expect(
        segmentEarliestDeparture(
          initial.copyWith(transportSelections: [legacy]),
          'B',
        ),
        32701,
      );
      expect(
        segmentEarliestDeparture(
          selected.copyWith(travelDate: DateTime(2026, 6, 2)),
          'B',
        ),
        28800,
      );
    },
  );
  testWidgets(
    'automatic shared search filters by previous arrival locally without repeat requests',
    (tester) async {
      final spots = [spot('A'), spot('B'), spot('C')],
          repo = LocalTripsRepository(storage: MemorySettingsStorage());
      await repo.save(
        TripLibrary(
          plans: [
            TripState(
              stops: spots,
              saved: spots,
              travelDate: DateTime(2026, 6, 1),
            ),
          ],
        ),
      );
      final calls = <String, int>{};
      final requests = <Json>[];
      final aToB = [
        journey('to-b', 'a', 'b', 480, 540),
        journey('later-to-b', 'a', 'b', 510, 585),
      ];
      final bToC = [
        journey('early', 'b', 'c', 510, 530),
        journey('on-time', 'b', 'c', 540, 560),
        journey('later', 'b', 'c', 570, 590),
      ];
      final container = ProviderContainer(
        overrides: [
          catalogProvider.overrideWith(
            (ref) => Stream.value(TravelCatalog(experiences: spots)),
          ),
          tripsRepositoryProvider.overrideWithValue(repo),
          transportDataProvider.overrideWith(
            (ref, key) async => TransportData([], [], [], [], []),
          ),
          journeySearchProvider.overrideWithValue((q) async {
            requests.add(q);
            final from = ((q['from'] as List).first as Map)['stopId'] as String;
            calls[from] = (calls[from] ?? 0) + 1;
            return JourneySearchResult({
              'journeys': from == 'a' ? aToB : bToC,
              'warnings': ['徒歩時間が未登録です'],
            });
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
          child: const MaterialApp(home: ItineraryEditor()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('出発時刻 08:00'), findsOneWidget);
      expect(calls['a'], 1);
      expect(requests.single['departureSeconds'], 28800);
      expect(requests.single['timetable'], true);
      expect(find.textContaining('最小乗換時間'), findsNothing);
      expect(find.byKey(const ValueKey('search-transfers')), findsNothing);
      expect(find.textContaining('徒歩時間が未登録'), findsNothing);
      expect(find.textContaining('乗場ID'), findsNothing);
      final choose = find.byKey(const ValueKey('choose-to-b-1-2'));
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      void openB() => tester
          .widgetList<ItinerarySpotCard>(find.byType(ItinerarySpotCard))
          .firstWhere((w) => w.spot.id == 'B')
          .onSelect();
      openB();
      await tester.pumpAndSettle();
      expect(calls['b'], 1);
      expect(find.byKey(const ValueKey('candidate-early-1-2')), findsNothing);
      expect(
        find.byKey(const ValueKey('candidate-on-time-1-2')),
        findsOneWidget,
      );
      container
          .read(tripProvider.notifier)
          .selectTransport(TransportJourney(aToB.last).selection('A', 'B'));
      await tester.pumpAndSettle();
      expect(calls['b'], 1);
      expect(find.byKey(const ValueKey('candidate-later-1-2')), findsNothing);
      container.read(tripProvider.notifier).clearTransport('A', 'B');
      await tester.pumpAndSettle();
      expect(calls['b'], 1);
      expect(find.byKey(const ValueKey('candidate-early-1-2')), findsOneWidget);
      container.read(tripProvider.notifier).setDepartureMinutes(600);
      await tester.pumpAndSettle();
      expect(calls['b'], 2);
      expect(requests.last['departureSeconds'], 36000);
      expect(find.text('出発時刻 10:00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('itinerary-departure-time')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TimePickerDialog>(find.byType(TimePickerDialog))
            .initialTime,
        const TimeOfDay(hour: 10, minute: 0),
      );
      final timeInputs = find.byType(TextField);
      await tester.enterText(timeInputs.first, '09');
      await tester.enterText(timeInputs.last, '15');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider).departureMinutes, 555);
      expect(find.text('出発時刻 09:15'), findsOneWidget);
      await container.read(tripLibraryProvider.notifier).flush();
      expect((await repo.load()).activeTrip!.departureMinutes, 555);
      expect((await repo.load()).activeTrip!.travelDate, DateTime(2026, 6, 1));
    },
  );
}
