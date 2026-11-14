import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'package:sightseeing_matching_app/data/departure_places.dart';
import 'package:sightseeing_matching_app/model/ai_trip_draft.dart';
import 'package:sightseeing_matching_app/model/ai_trip_segment.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/model/travel_catalog.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/screen/itinerary/ai_trip_panel.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_home.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_editor.dart';
import 'package:sightseeing_matching_app/state/itinerary_setup_state.dart';
import 'package:sightseeing_matching_app/widgets/departure_map.dart';
import 'package:sightseeing_matching_app/model/transport_journey.dart';
import 'package:sightseeing_matching_app/repository/transport_journey_repository.dart';
import 'package:sightseeing_matching_app/repository/transport_repository.dart';
import 'package:sightseeing_matching_app/screen/itinerary/ai_transport_card.dart';
import 'package:sightseeing_matching_app/service/transport/ai_trip_repository.dart';
import 'package:sightseeing_matching_app/service/transport/transport_itinerary_service.dart';
import 'package:sightseeing_matching_app/state/experience_photos.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'departure_fixtures.dart';
import 'test_support.dart';

final a = Experience(
  'a',
  'A',
  '',
  '',
  '',
  '',
  '',
  '',
  30,
  accessStops: [
    AccessStop({
      'stopId': 'a-stop',
      'walkingMinutes': 5,
      'verificationStatus': 'unverified',
    }),
  ],
);
final b = Experience(
  'b',
  'B',
  '',
  '',
  '',
  '',
  '',
  '',
  40,
  accessStops: [
    AccessStop({
      'stopId': 'b-stop',
      'walkingMinutes': 3,
      'verificationStatus': 'verified',
    }),
  ],
);
final endpoints = [
  DeparturePlace(
    departurePlaces.first.id,
    '札幌駅',
    '',
    departurePlaces.first.point,
    accessStops: [
      AccessStop({
        'stopId': 'subway',
        'stopName': 'さっぽろ',
        'walkingMinutes': null,
      }),
      AccessStop({
        'stopId': 'jr_hokkaido~sapporo',
        'stopName': '札幌',
        'walkingMinutes': null,
      }),
    ],
  ),
  DeparturePlace(
    '小樽駅',
    '小樽駅',
    '',
    departurePlaces[2].point,
    accessStops: [
      AccessStop({
        'stopId': 'jr_hokkaido~otaru',
        'stopName': '小樽',
        'walkingMinutes': null,
      }),
    ],
  ),
];

class FakeAiRepository extends AiTripRepository {
  FakeAiRepository() : super(() => throw StateError('No live Firebase'));
  @override
  Future<Json> register(TripState trip) async => {
    'tripId': 'root',
    'aiGenerationStatus': trip.aiStatus == 'completed' ? 'completed' : 'unused',
  };
  @override
  Future<Json?> read(String id) async => {'aiGenerationStatus': 'failed'};
  @override
  Future<void> save(TripState trip) async {}
  @override
  Stream<Json> watch(String id) => const Stream.empty();
}

Json generated() => {
  'success': true,
  'message': '成功',
  'aiMetadata': {
    'visitOrder': ['b', 'a'],
    'lookup': {
      'agencies': [
        {'id': 'operator', 'name': '登録事業者'},
      ],
      'routes': [
        {'id': 'r', 'name': '登録路線', 'agencyId': 'operator'},
      ],
      'stops': [
        {'id': 's', 'name': '札幌'},
        {'id': 't', 'name': '新夕張'},
      ],
    },
  },
  'itinerary': {
    'status': 'feasible',
    'candidateId': 'one',
    'requiresReview': true,
    'summary': {'departureSeconds': 28800, 'arrivalSeconds': 44000},
    'visits': [
      {'spotId': 'b', 'arrivalSeconds': 35000, 'departureSeconds': 37400},
      {'spotId': 'a', 'arrivalSeconds': 40000, 'departureSeconds': 41800},
    ],
    'legs': [
      {
        'fromPlaceId': '札幌駅',
        'toPlaceId': 'b',
        'departureSeconds': 28800,
        'arrivalSeconds': 35000,
        'steps': [
          {
            'kind': 'transit',
            'routeId': 'r',
            'fromStopId': 's',
            'toStopId': 't',
            'departureSeconds': 28800,
            'arrivalSeconds': 35000,
          },
        ],
      },
      {
        'fromPlaceId': 'b',
        'toPlaceId': 'a',
        'departureSeconds': 37400,
        'arrivalSeconds': 40000,
        'steps': [
          {
            'kind': 'transit',
            'routeId': 'r',
            'fromStopId': 't',
            'toStopId': 's',
            'departureSeconds': 37400,
            'arrivalSeconds': 40000,
          },
        ],
      },
      {
        'fromPlaceId': 'a',
        'toPlaceId': '札幌駅',
        'departureSeconds': 41800,
        'arrivalSeconds': 44000,
        'steps': [
          {
            'kind': 'transit',
            'routeId': 'r',
            'fromStopId': 't',
            'toStopId': 's',
            'departureSeconds': 41800,
            'arrivalSeconds': 44000,
          },
        ],
      },
    ],
  },
};
Future<ProviderContainer> scope(
  TripState trip, {
  TransportItineraryService? service,
  List<DeparturePlace>? places,
}) async {
  final repo = LocalTripsRepository(storage: MemorySettingsStorage());
  await repo.save(TripLibrary(plans: [trip]));
  final c = ProviderContainer(
    overrides: [
      tripsRepositoryProvider.overrideWithValue(repo),
      mapTilesEnabledProvider.overrideWithValue(false),
      itineraryJourneysProvider.overrideWith(
        (ref, key) async =>
            JourneySearchResult({'journeys': [], 'warnings': []}),
      ),
      transportDataProvider.overrideWith(
        (ref, key) async => TransportData([], [], [], [], []),
      ),
      aiTripRepositoryProvider.overrideWithValue(FakeAiRepository()),
      departurePlacesProvider.overrideWith(
        (ref) => Stream.value(places ?? endpoints),
      ),
      catalogProvider.overrideWith(
        (ref) => Stream.value(TravelCatalog(experiences: [a, b])),
      ),
      experiencePhotosProvider.overrideWith((ref) async => {}),
      if (service != null)
        transportItineraryServiceProvider.overrideWithValue(service),
    ],
  );
  await c.read(tripLibraryProvider.future);
  return c;
}

TripState initial({TripLength length = TripLength.day}) => TripState(
  id: 'trip',
  stops: [a, b],
  saved: [a, b],
  travelDate: DateTime(2026, 11, 1),
  conditions: SearchConditions(length: length),
);
TripState completed() {
  var trip = initial().copyWith(
    stops: [b, a],
    ai: {'status': 'completed', 'result': generated(), 'enabled': true},
  );
  return trip.copyWith(ai: {...trip.ai, 'basis': trip.aiBasis});
}

Future<void> panel(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AiTripPanel())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'setup AI opens the existing editor and a completed itinerary can generate again',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <String>[];
      final c = await scope(
        initial(),
        service: TransportItineraryService(
          isAuthenticated: () async => true,
          invoke: (input) async {
            requests.add(input['requestId'] as String);
            return generated();
          },
        ),
      );
      addTearDown(c.dispose);
      c.read(itinerarySetupProvider.notifier).toggle('a');
      c.read(itinerarySetupProvider.notifier).toggle('b');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: ItineraryHome()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('setup-create-ai')));
      await tester.pumpAndSettle();
      expect(find.byType(ItineraryEditor), findsOneWidget);
      expect(find.byType(AiTripConditionsSheet), findsOneWidget);
      expect(requests, isEmpty);
      await tester.tap(find.text('AIで旅程を作成'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(find.byType(PlanScreen), findsOneWidget);
      expect(c.read(tripProvider).aiLocked, false);
      final tripId = c.read(tripProvider).id;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-create-trip')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AIで旅程を作成'));
      await tester.pumpAndSettle();
      expect(requests.toSet(), hasLength(2));
      expect(c.read(tripProvider).id, tripId);
      expect(c.read(tripProvider).aiStatus, 'completed');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('setup-create-manual')));
      await tester.pumpAndSettle();
      expect(find.byType(AiTripConditionsSheet), findsNothing);
      expect(requests, hasLength(2));
      expect(tester.takeException(), isNull);
      await c.read(tripLibraryProvider.notifier).flush();
    },
  );

  test(
    'AI result and editable trip persist separately; order, time, destination and stays invalidate routes',
    () {
      final trip = completed();
      final restored = TripState.fromJson(
        jsonDecode(jsonEncode(trip.toJson())) as Json,
      );
      expect(restored.aiProposalValid, true);
      expect(restored.aiLocked, false);
      for (final t in [
        restored.copyWith(stops: [a, b]),
        restored.copyWith(stayMinutes: {'a': 99}),
        restored.copyWith(departureMinutes: 900),
        restored.copyWith(destination: '小樽駅'),
      ]) {
        expect(t.aiProposalValid, false);
        expect(t.aiStatus, 'completed');
      }
      expect(aiTripSegments(restored), hasLength(3));
    },
  );
  test(
    'both place legs and flat steps map into three adjacent transport segments',
    () {
      final trip = completed();
      expect(aiTripSegments(trip).map((s) => s.steps.length), [1, 1, 1]);
      expect(aiTripSegments(trip).first.routeNames, '登録事業者 · 登録路線');
      final response = generated();
      final itinerary = response['itinerary'] as Map;
      itinerary['legs'] = [
        for (final l in itinerary['legs'] as List) ...l['steps'] as List,
      ];
      final flat = trip.copyWith(ai: {...trip.ai, 'result': response});
      expect(aiTripSegments(flat).map((s) => s.departureSeconds), [
        28800,
        37400,
        41800,
      ]);
    },
  );
  test(
    'manual traffic selection invalidates connected AI suggestions; duplication preserves AI quota',
    () async {
      final c = await scope(completed());
      addTearDown(c.dispose);
      c
          .read(tripProvider.notifier)
          .selectTransport(
            TransportSelection({
              'fromSpotId': 'b',
              'toSpotId': 'a',
              'selectedTripId': 'manual',
            }),
          );
      final trip = c.read(tripProvider);
      expect(activeAiTripSegment(trip, 'b', 'a'), isNull);
      expect(activeAiTripSegment(trip, trip.originEndpointId, 'b'), isNull);
      expect(trip.ai['enabled'], false);
      expect(aiTripSegments(trip), hasLength(3));
      c.read(tripLibraryProvider.notifier).duplicate('trip');
      expect(c.read(tripProvider).aiStatus, 'completed');
      expect(c.read(tripProvider).ai['lineage'], 'trip');
      await c.read(tripLibraryProvider.notifier).flush();
    },
  );
  test(
    'a late response stores its source without overwriting manual edits',
    () async {
      final c = await scope(initial());
      addTearDown(c.dispose);
      final n = c.read(tripProvider.notifier),
          basis = c.read(tripProvider).aiBasis;
      n.setStay('a', 99);
      n.acceptAi(generated(), basis);
      expect(c.read(tripProvider).stops.map((e) => e.id), ['a', 'b']);
      expect(c.read(tripProvider).stayMinutes['a'], 99);
      expect(c.read(tripProvider).aiProposalValid, false);
      await c.read(tripLibraryProvider.notifier).flush();
    },
  );
  test(
    'visit hours persist with the trip while matching card serialization remains unchanged',
    () {
      expect(
        tripOpening(a, DateTime(2026, 11, 1), DateTime(2026, 11, 3))['windows'],
        [
          [0, 259200],
        ],
      );
      final spot = Experience.fromJson({
        ...a.toJson(),
        'openingHoursStatus': 'always_open',
      });
      expect(spot.toJson(), a.toJson());
      final restored = TripState.fromJson(
        initial().copyWith(stops: [spot]).toJson(),
      );
      expect(
        restored.stops.single.visitInfo['openingHoursStatus'],
        'always_open',
      );
    },
  );
  test(
    'JR Sapporo is default even with unregistered walking, and nights derive the arrival date',
    () {
      expect(
        defaultBoardingStop('札幌駅', endpoints.first.accessStops)!.stopId,
        'jr_hokkaido~sapporo',
      );
      expect(
        tripArrivalDate(DateTime(2026, 11, 1), TripLength.overnight),
        DateTime(2026, 11, 2),
      );
      expect(
        tripArrivalDate(DateTime(2026, 11, 1), TripLength.longer),
        DateTime(2026, 11, 3),
      );
    },
  );
  test(
    'unknown opening is assumed available; registered closure and special hours take precedence',
    () {
      expect(tripOpening(a, DateTime(2026, 11, 1), DateTime(2026, 11, 1)), {
        'status': 'known',
        'windows': [
          [0, 86400],
        ],
        'assumedOpen': true,
      });
      expect(
        tripOpening(a, DateTime(2026, 11, 1), DateTime(2026, 11, 3))['windows'],
        [
          [0, 259200],
        ],
      );
      final spot = Experience.fromJson({
        ...a.toJson(),
        'visitInfo': {
          'openingHoursStatus': 'always_open',
          'specialHours': [
            {'date': '2026-11-01', 'closed': true, 'hours': [], 'note': ''},
          ],
        },
      });
      expect(
        tripOpening(
          spot,
          DateTime(2026, 11, 1),
          DateTime(2026, 11, 1),
        )['status'],
        'closed',
      );
    },
  );
  testWidgets(
    'completed trips can regenerate; quota-blocked trips remain disabled',
    (tester) async {
      for (final state in [
        {'status': 'completed'},
        {
          'status': 'failed',
          'blockedUntil': DateTime.now()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        },
      ]) {
        final c = await scope(initial().copyWith(ai: state));
        await panel(tester, c);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('ai-create-trip')),
              )
              .onPressed,
          state['status'] == 'completed' ? isNotNull : isNull,
        );
        expect(find.textContaining('観光地の順番と'), findsNothing);
        expect(find.text('AI提案を採用'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await c.read(tripLibraryProvider.notifier).flush();
        c.dispose();
      }
    },
  );
  for (final success in [true, false]) {
    testWidgets(
      'minimal condition sheet; generation=$success automatically opens booklet only on success',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var calls = 0;
        final trip = initial(length: TripLength.overnight);
        final c = await scope(
          trip,
          service: TransportItineraryService(
            isAuthenticated: () async => true,
            invoke: (input) async {
              calls++;
              final q = input['input'] as Map;
              expect(q['deadlineSeconds'], 86400 + 64800);
              expect((q['origin'] as Map)['accessStops'], [
                {
                  'stopId': 'jr_hokkaido~sapporo',
                  'stopName': '札幌',
                  'walkingMinutes': 0,
                  'verificationStatus': 'verified',
                },
              ]);
              expect(
                (q['visits'] as List).first['opening']['assumedOpen'],
                true,
              );
              return success ? generated() : {'success': false};
            },
          ),
        );
        addTearDown(c.dispose);
        await panel(tester, c);
        await tester.tap(find.byKey(const ValueKey('ai-create-trip')));
        await tester.pumpAndSettle();
        expect(find.text('JR北海道「札幌」'), findsNWidgets(2));
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(find.textContaining('営業時間'), findsNothing);
        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(calls, 0);
        await tester.tap(find.text('AIで旅程を作成'));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(
          find.byType(PlanScreen),
          success ? findsOneWidget : findsNothing,
        );
        expect(c.read(tripProvider).aiStatus, success ? 'completed' : 'failed');
        if (success) {
          expect(find.byType(AiTransportCard), findsWidgets);
          expect(find.text('AI提案を採用'), findsNothing);
        } else {
          expect(c.read(tripProvider).stops.map((e) => e.id), ['a', 'b']);
        }
        expect(tester.takeException(), isNull);
        await c.read(tripLibraryProvider.notifier).flush();
      },
    );
  }
  testWidgets(
    'arrival place may differ from departure and narrow sheet stays usable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = await scope(initial());
      addTearDown(c.dispose);
      await panel(tester, c);
      await tester.tap(find.byKey(const ValueKey('ai-create-trip')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('ai-destination-place'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('小樽駅').last);
      await tester.pumpAndSettle();
      expect(find.text('JR北海道「小樽」'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await c.read(tripLibraryProvider.notifier).flush();
    },
  );
}
