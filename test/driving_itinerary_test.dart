import 'package:sightseeing_matching_app/screen/itinerary/widgets/itinerary_spot_card.dart';
import 'package:sightseeing_matching_app/repository/driving_schedule_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'package:sightseeing_matching_app/data/departure_places.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/repository/driving_route_repository.dart';
import 'package:sightseeing_matching_app/repository/transport_journey_repository.dart';
import 'package:sightseeing_matching_app/repository/transport_repository.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_editor.dart';
import 'package:sightseeing_matching_app/screen/bookmark/widgets/bookmark_timeline.dart';
import 'package:sightseeing_matching_app/screen/itinerary/widgets/car_transport_options.dart';
import 'package:sightseeing_matching_app/service/transport/driving_schedule.dart';
import 'package:sightseeing_matching_app/state/experience_photos.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'package:sightseeing_matching_app/widgets/departure_map.dart';
import 'departure_fixtures.dart';
import 'test_support.dart';

const a = Experience(
  'car-a',
  '観光地A',
  '',
  '',
  '',
  '',
  '',
  '',
  60,
  address: '札幌市中央区',
  latitude: 43.05,
  longitude: 141.35,
);
const b = Experience(
  'car-b',
  '観光地B',
  '',
  '',
  '',
  '',
  '',
  '',
  30,
  address: '夕張市',
  latitude: 43.06,
  longitude: 141.36,
);
TripState plan() => TripState(
  id: 'car-plan',
  stops: [a, b],
  saved: [a, b],
  travelDate: DateTime(2026, 11, 17),
  conditions: const SearchConditions(transport: TravelMode.car),
);
TransportSelection selection(
  TripState trip,
  String from,
  String to,
  int departure,
  int arrival,
) => TransportSelection({
  'mode': 'car',
  'fromSpotId': from,
  'toSpotId': to,
  'selectedTripId': 'car-$from-$to',
  'departureMinutes': departure,
  'arrivalMinutes': arrival,
  'serviceDate': drivingServiceDate(trip),
  'distanceMeters': 20000,
  'durationSeconds': (arrival - departure) * 60,
});

void main() {
  initializeCatalogTests();
  Future<ProviderContainer> containerFor(
    TripState trip, {
    Future<Json> Function(Json)? search,
  }) async {
    final repo = LocalTripsRepository(storage: MemorySettingsStorage());
    await repo.save(TripLibrary(plans: [trip], activeId: trip.id));
    final container = ProviderContainer(
      overrides: [
        tripsRepositoryProvider.overrideWithValue(repo),
        catalogProvider.overrideWith((ref) => Stream.value(testCatalog)),
        departurePlacesProvider.overrideWith(
          (ref) => Stream.value(departurePlaces),
        ),
        experiencePhotosProvider.overrideWith((ref) async => {}),
        mapTilesEnabledProvider.overrideWithValue(false),
        drivingRouteSearchProvider.overrideWithValue(
          search ??
              (_) async => {
                'durationSeconds': 1234,
                'distanceMeters': 20000,
                'provider': 'google_routes',
              },
        ),
        transportDataProvider.overrideWith(
          (ref, key) async => throw StateError('public transit must not load'),
        ),
        journeySearchProvider.overrideWithValue(
          (_) async => throw StateError('public journeys must not load'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(tripLibraryProvider.future);
    container.read(tripProvider.notifier).openPlan(trip.id);
    return container;
  }

  test('legacy either migrates to transit and only two modes remain', () {
    expect(TravelMode.values, [TravelMode.transit, TravelMode.car]);
    expect(
      SearchConditions.fromJson({'transport': 2}).transport,
      TravelMode.transit,
    );
    expect(
      SearchConditions.fromJson({'transport': 1}).transport,
      TravelMode.car,
    );
  });

  List<Experience> pointsFor(TripState trip) => [
    Experience(
      trip.originEndpointId,
      trip.origin,
      '',
      '',
      '',
      '',
      '',
      '',
      0,
      latitude: 43.06,
      longitude: 141.35,
    ),
    ...trip.stops,
    Experience(
      trip.destinationEndpointId,
      trip.arrivalPlace,
      '',
      '',
      '',
      '',
      '',
      '',
      0,
      latitude: 43.06,
      longitude: 141.35,
    ),
  ];

  test(
    'default schedules persist and recalculate after time, stay and date changes',
    () async {
      final trip = plan();
      final container = await containerFor(trip);
      final controller = container.read(tripProvider.notifier);
      Future<void> sync() async {
        final current = container.read(tripProvider);
        final result = await container.read(
          drivingScheduleProvider(
            drivingScheduleKey(current, pointsFor(current)),
          ).future,
        );
        controller.syncCarTransport(result);
      }

      await sync();
      var selections = container.read(tripProvider).transportSelections;
      expect(selections.map((s) => s.data['departureMinutes']), [
        480,
        561,
        612,
      ]);
      expect(selections.map((s) => s.data['arrivalMinutes']), [501, 582, 633]);
      await container.read(tripLibraryProvider.notifier).flush();
      final restored = await container.read(tripsRepositoryProvider).load();
      expect(restored.plans.single.transportSelections, hasLength(3));
      controller.setStay(a.id, 90);
      await sync();
      expect(
        container
            .read(tripProvider)
            .transportSelections[1]
            .data['departureMinutes'],
        591,
      );
      controller.selectCarTransport(
        TransportSelection({
          ...selection(trip, trip.originEndpointId, a.id, 500, 521).data,
          'departureOverride': true,
          'requestedDepartureMinutes': 500,
        }),
      );
      await sync();
      expect(
        container
            .read(tripProvider)
            .transportSelections[1]
            .data['departureMinutes'],
        611,
      );
      controller.setDate(DateTime(2026, 11, 18));
      await sync();
      expect(container.read(tripProvider).transportSelections, hasLength(3));
      expect(
        container
            .read(tripProvider)
            .transportSelections
            .first
            .data['serviceDate'],
        '2026-11-18',
      );
      controller.setTravelMode(TravelMode.transit);
      expect(container.read(tripProvider).transportSelections, isEmpty);
    },
  );

  test(
    'car schedules continue beyond 28:00 and format overnight times',
    () async {
      final trip = plan().copyWith(departureMinutes: 23 * 60 + 50);
      final container = await containerFor(
        trip,
        search: (_) async => {
          'durationSeconds': 6 * 3600,
          'distanceMeters': 200000,
          'provider': 'google_routes',
        },
      );
      final schedule = await container.read(
        drivingScheduleProvider(
          drivingScheduleKey(trip, pointsFor(trip)),
        ).future,
      );
      expect(schedule.first.data['arrivalMinutes'], 1790);
      expect(schedule.last.data['arrivalMinutes'], 2600);
      expect(drivingTime(1440), '翌日0:00');
      expect(drivingTime(1790), '翌日5:50');
      expect(drivingTime(2600), '翌日19:20');
      expect(drivingTime(2880), '2日後0:00');
    },
  );

  test(
    'same-location detection requires matching nonempty addresses or valid coordinates',
    () {
      expect(
        sameDrivingLocation(
          {'address': '北海道 夕張市１－２'},
          {'address': '北海道夕張市1-2'},
        ),
        isTrue,
      );
      expect(sameDrivingLocation({'address': ''}, {'address': ''}), isFalse);
      expect(
        sameDrivingLocation(
          {'latitude': 43, 'longitude': 141},
          {'latitude': 43, 'longitude': 141},
        ),
        isTrue,
      );
      expect(
        sameDrivingLocation(
          {'address': '1', 'latitude': 43, 'longitude': 141},
          {'address': '2', 'latitude': 44, 'longitude': 141},
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'same-address stops are walkable without API requests and do not stop automatic scheduling',
    (tester) async {
      final first = Experience.fromJson({...a.toJson(), 'name': '栗下食堂'});
      final second = Experience.fromJson({
        ...b.toJson(),
        'name': '道の駅メロード',
        'address': a.address,
      });
      final trip = plan().copyWith(stops: [first, second]);
      var calls = 0;
      final container = await containerFor(
        trip,
        search: (query) async {
          calls++;
          expect(
            sameDrivingLocation(query['from'] as Map, query['to'] as Map),
            isFalse,
          );
          return {
            'durationSeconds': 1234,
            'distanceMeters': 20000,
            'provider': 'google_routes',
          };
        },
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ItineraryEditor()),
        ),
      );
      await tester.pump();
      final bottomBooklet = find.byKey(
        const ValueKey('itinerary-open-booklet'),
      );
      expect(tester.widget<OutlinedButton>(bottomBooklet).onPressed, isNotNull);
      expect(bottomBooklet.hitTestable(), findsOneWidget);
      await tester.pumpAndSettle();
      final selections = container.read(tripProvider).transportSelections;
      expect(selections, hasLength(3));
      expect(selections[1].data['walkingOnly'], isTrue);
      expect(selections[1].data['arrivalMinutes'], 561);
      expect(selections[2].data['departureMinutes'], 591);
      expect(selections[2].data['arrivalMinutes'], 612);
      expect(calls, 2);
      tester
          .widgetList<ItinerarySpotCard>(find.byType(ItinerarySpotCard))
          .firstWhere((card) => card.spot.id == first.id)
          .onSelect();
      await tester.pumpAndSettle();
      expect(find.text('この区間は徒歩で移動できます'), findsOneWidget);
      expect(find.textContaining('車ルートを取得できませんでした'), findsNothing);
      expect(calls, 2);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BookmarkTimeline(trip: container.read(tripProvider)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final walking = find.text('徒歩で移動');
      await tester.ensureVisible(walking);
      await tester.tap(walking);
      await tester.pumpAndSettle();
      expect(find.text('この区間は徒歩で移動できます'), findsOneWidget);
      expect(find.textContaining('約0分'), findsNothing);
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'overnight times remain prominent on a narrow screen without date or save controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final trip = plan().copyWith(departureMinutes: 1430);
      final container = await containerFor(
        trip,
        search: (_) async => {
          'durationSeconds': 21600,
          'distanceMeters': 200000,
          'provider': 'google_routes',
        },
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ItineraryEditor()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('car-arrival-label')))
            .data,
        '翌日5:50',
      );
      expect(
        container
            .read(tripProvider)
            .transportSelections
            .last
            .data['arrivalMinutes'],
        2600,
      );
      expect(find.textContaining('28:00'), findsNothing);
      expect(find.byKey(const ValueKey('save-car-transport')), findsNothing);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('car-travel-times'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('car-departure-time')))
              .dy,
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('car-open-maps'))).height,
        greaterThanOrEqualTo(56),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'car sheet saves route times, disables AI and booklet shows driving information',
    (tester) async {
      final trip = plan();
      var calls = 0;
      final container = await containerFor(
        trip,
        search: (query) async {
          calls++;
          expect((query['to'] as Map)['name'], isNotEmpty);
          return {
            'durationSeconds': 1234,
            'distanceMeters': 20000,
            'provider': 'google_routes',
          };
        },
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ItineraryEditor()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CarTransportOptions), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('car-departure-label')))
            .data,
        '8:00',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('car-arrival-label')))
            .data,
        '8:21',
      );
      expect(container.read(tripProvider).transportSelections, hasLength(3));
      expect(find.byKey(const ValueKey('save-car-transport')), findsNothing);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(calls, 3);
      final ai = find.byKey(const ValueKey('ai-create-trip'));
      expect(tester.widget<OutlinedButton>(ai).onPressed, isNull);
      await tester.tapAt(tester.getCenter(ai));
      await tester.pumpAndSettle();
      expect(find.text('車での移動はAIルート検索に対応していません。'), findsOneWidget);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('transport-sheet-header')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      final departureTime = find.byKey(const ValueKey('car-departure-time'));
      await tester.ensureVisible(departureTime);
      await tester.tap(departureTime);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '09');
      await tester.enterText(find.byType(TextField).at(1), '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('car-arrival-label')))
            .data,
        '9:51',
      );
      final saved = container.read(tripProvider).transportSelections.first;
      expect(
        container
            .read(tripProvider)
            .transportSelections[1]
            .data['departureMinutes'],
        651,
      );
      expect(saved.data['mode'], 'car');
      expect(container.read(tripProvider).departureMinutes, 570);
      expect(saved.data['departureMinutes'], 570);
      expect(saved.data['arrivalMinutes'], 591);
      expect(calls, 3);
      expect(find.byKey(const ValueKey('car-open-maps')), findsOneWidget);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BookmarkTimeline(trip: container.read(tripProvider)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('車で移動 · 約21分'), findsNWidgets(3));
      await tester.tap(find.text('車で移動 · 約21分').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('9:51 到着予定'), findsOneWidget);
      expect(find.textContaining('乗車停留所'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
