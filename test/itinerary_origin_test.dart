import 'package:sightseeing_matching_app/screen/bookmark/bookmark_home.dart';
import 'package:sightseeing_matching_app/state/app_tab.dart';
import 'departure_fixtures.dart';
import 'package:sightseeing_matching_app/data/departure_places.dart';
import 'package:sightseeing_matching_app/repository/transport_journey_repository.dart';
import 'package:sightseeing_matching_app/model/transport_journey.dart';
import 'package:sightseeing_matching_app/screen/itinerary/widgets/itinerary_transport_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/model/travel_catalog.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/repository/transport_repository.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_editor.dart';
import 'package:sightseeing_matching_app/screen/itinerary/widgets/itinerary_endpoint_card.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'package:sightseeing_matching_app/widgets/departure_map.dart';
import 'test_support.dart';

void main() {
  final first = Experience(
    'first',
    '紹介文',
    '地域',
    '自然',
    '紹介',
    '',
    '',
    '',
    60,
    name: '最初の観光地',
    accessStops: [
      AccessStop({'stopId': 'b', 'walkingMinutes': 8}),
    ],
  );
  test(
    'origin selections survive edits and reload but invalidate on origin or first-spot change',
    () async {
      final trip = TripState(
        stops: [first],
        conditions: const SearchConditions(origin: '札幌駅'),
      );
      final selected = trip.copyWith(
        transportSelections: [
          TransportSelection({
            'fromSpotId': trip.originEndpointId,
            'toSpotId': first.id,
            'selectedTripId': 't',
          }),
        ],
      );
      expect(selected.transportSelections, hasLength(1));
      expect(
        selected.copyWith(stayMinutes: {first.id: 90}).transportSelections,
        hasLength(1),
      );
      expect(
        selected
            .copyWith(conditions: const SearchConditions(origin: '小樽駅'))
            .transportSelections,
        isEmpty,
      );
      expect(selected.copyWith(stops: []).transportSelections, isEmpty);
      expect(
        selected
            .copyWith(
              stops: [
                const Experience('other', '別の場所', '', '', '', '', '', '', 30),
                first,
              ],
            )
            .transportSelections,
        isEmpty,
      );
      final repo = LocalTripsRepository(storage: MemorySettingsStorage());
      await repo.save(TripLibrary(plans: [selected]));
      expect(
        (await repo.load()).activeTrip!.transportSelections.single.from,
        trip.originEndpointId,
      );
    },
  );
  for (final outcome in ['registered', 'empty', 'error']) {
    testWidgets(
      'departure icon selects the first leg with $outcome transport data',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 568));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final trip = TripState(
          stops: [first],
          saved: [first],
          conditions: const SearchConditions(origin: '札幌駅'),
        );
        final repo = LocalTripsRepository(storage: MemorySettingsStorage());
        await repo.save(TripLibrary(plans: [trip]));
        final data = TransportData(
          [
            TransportStop('a', {'name': '札幌駅'}),
            TransportStop('b', {'name': '観光地前'}),
          ],
          [
            TransportRoute('r', {'name': '登録路線', 'mode': 'bus'}),
          ],
          [
            TransportTrip('t', {
              'routeId': 'r',
              'serviceId': 's',
              'verificationStatus': 'sample',
              'stopTimes': [
                {'stopId': 'a', 'sequence': 1, 'departureMinutes': 490},
                {'stopId': 'b', 'sequence': 2, 'arrivalMinutes': 520},
              ],
            }),
          ],
          [],
          [],
        );
        var originLoads = 0;
        final container = ProviderContainer(
          overrides: [
            departurePlacesProvider.overrideWith(
              (ref) => Stream.value(departurePlaces),
            ),
            tripsRepositoryProvider.overrideWithValue(repo),
            catalogProvider.overrideWith(
              (ref) => Stream.value(TravelCatalog(experiences: [first])),
            ),
            mapTilesEnabledProvider.overrideWithValue(false),
            itineraryJourneysProvider.overrideWith(
              (ref, key) async =>
                  JourneySearchResult({'journeys': [], 'warnings': []}),
            ),
            transportDataProvider.overrideWith((ref, key) async => data),
            originTransportStopsProvider.overrideWith((ref, origin) async {
              originLoads++;
              if (outcome == 'error') throw StateError('offline');
              return outcome == 'empty'
                  ? []
                  : [
                      TransportStop('a', {
                        'name': origin,
                        'sourceType': 'sample',
                        'verificationStatus': 'sample',
                      }),
                    ];
            }),
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
        expect(originLoads, 0);
        expect(find.byKey(const ValueKey('itinerary-home')), findsOneWidget);
        final departure = find.byKey(const ValueKey('itinerary-departure'));
        await tester.tap(departure);
        await tester.pumpAndSettle();
        expect(originLoads, 1);
        expect(
          tester.widget<ItineraryEndpointCard>(departure).selected,
          isTrue,
        );
        expect(find.text('札幌駅'), findsWidgets);
        if (outcome == 'registered') {
          final sheetFinder = find.byKey(
            const ValueKey('itinerary-transport-sheet'),
          );
          final sheet = tester.widget<DraggableScrollableSheet>(sheetFinder);
          final header = find.byKey(const ValueKey('transport-sheet-header'));
          final departureTime = find.byKey(
            const ValueKey('itinerary-departure-time'),
          );
          expect(sheet.snapSizes, hasLength(3));
          expect(
            tester.getTopLeft(header).dy,
            closeTo(
              [
                tester.getBottomLeft(departureTime).dy,
                tester
                    .getBottomLeft(find.byKey(const ValueKey('ai-create-trip')))
                    .dy,
              ].reduce((a, b) => a > b ? a : b),
              1,
            ),
          );
          for (final size in sheet.snapSizes!) {
            sheet.controller!.jumpTo(size);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(sheet.controller!.size, closeTo(size, .001));
            if (size == sheet.snapSizes![1]) {
              expect(
                tester.getTopLeft(header).dy,
                closeTo(
                  tester
                      .getTopLeft(find.byKey(const ValueKey('itinerary-map')))
                      .dy,
                  1,
                ),
              );
              // A short, slow drag must settle at the middle stop.
              await tester.timedDrag(
                header,
                const Offset(0, -5),
                const Duration(seconds: 1),
              );
              await tester.pumpAndSettle();
              expect(sheet.controller!.size, closeTo(size, .001));
            }
          }
          final choose = find.byKey(const ValueKey('choose-t-1-2'));
          await tester.scrollUntilVisible(
            choose,
            100,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('transport-sheet-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await Scrollable.ensureVisible(tester.element(choose), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(choose);
          await tester.pumpAndSettle();
          final selection = container
              .read(tripProvider)
              .transportSelections
              .single;
          expect(selection.from, trip.originEndpointId);
          expect(selection.to, first.id);
          expect(selection.data['walkingMinutesBefore'], isNull);
          await container.read(tripLibraryProvider.notifier).flush();
          expect(
            (await repo.load())
                .activeTrip!
                .transportSelections
                .single
                .data['selectedTripId'],
            't',
          );
          await tester.tap(
            find.byKey(const ValueKey('itinerary-view-booklet')),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('saved-transport-t')),
            140,
            scrollable: find.byType(Scrollable).last,
          );
          expect(
            find.byKey(const ValueKey('saved-transport-t')),
            findsOneWidget,
          );
        } else {
          expect(find.byKey(const ValueKey('choose-t-1-2')), findsNothing);
          expect(
            find.textContaining(
              outcome == 'error' ? '交通情報を取得できませんでした' : 'この区間の交通情報は未登録です。',
            ),
            findsOneWidget,
          );
        }
        expect(container.read(tripProvider).stops, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'return selections persist but invalidate when origin or last stop changes',
    () async {
      final trip = TripState(
        stops: [first],
        conditions: const SearchConditions(origin: '札幌駅'),
      );
      final selected = trip.copyWith(
        transportSelections: [
          TransportSelection({
            'fromSpotId': first.id,
            'toSpotId': trip.originEndpointId,
            'selectedTripId': 'back',
            'toKind': 'origin',
          }),
        ],
      );
      expect(selected.transportSelections, hasLength(1));
      expect(
        selected.copyWith(title: '旅の名前').transportSelections,
        hasLength(1),
      );
      expect(
        selected.copyWith(stayMinutes: {first.id: 90}).transportSelections,
        hasLength(1),
      );
      expect(
        selected
            .copyWith(conditions: const SearchConditions(origin: '小樽駅'))
            .transportSelections,
        isEmpty,
      );
      expect(
        selected
            .copyWith(
              stops: [
                first,
                const Experience('other', '別の場所', '', '', '', '', '', '', 30),
              ],
            )
            .transportSelections,
        isEmpty,
      );
      final repo = LocalTripsRepository(storage: MemorySettingsStorage());
      await repo.save(TripLibrary(plans: [selected]));
      expect(
        (await repo.load()).activeTrip!.transportSelections.single.to,
        trip.originEndpointId,
      );
    },
  );
  for (final target in ['last', 'last-many', 'no-return']) {
    testWidgets('return to origin via $target card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final planned = [
        if (target == 'last-many')
          const Experience('earlier', '前の観光地', '', '', '', '', '', '', 30),
        first,
      ];
      final trip = TripState(
        stops: planned,
        saved: planned,
        conditions: const SearchConditions(origin: '札幌駅'),
      );
      final repo = LocalTripsRepository(storage: MemorySettingsStorage());
      await repo.save(TripLibrary(plans: [trip]));
      final data = TransportData(
        [
          TransportStop('a', {'name': '札幌駅'}),
          TransportStop('b', {'name': '観光地前'}),
        ],
        [
          TransportRoute('r', {'name': '登録路線', 'mode': 'bus'}),
        ],
        [
          TransportTrip('outbound', {
            'routeId': 'r',
            'serviceId': 's',
            'verificationStatus': 'sample',
            'stopTimes': [
              {'stopId': 'a', 'sequence': 1, 'departureMinutes': 490},
              {'stopId': 'b', 'sequence': 2, 'arrivalMinutes': 520},
            ],
          }),
          if (target != 'no-return')
            TransportTrip('back', {
              'routeId': 'r',
              'serviceId': 's',
              'verificationStatus': 'sample',
              'stopTimes': [
                {'stopId': 'b', 'sequence': 1, 'departureMinutes': 1000},
                {'stopId': 'a', 'sequence': 2, 'arrivalMinutes': 1030},
              ],
            }),
        ],
        [],
        [],
      );
      final container = ProviderContainer(
        overrides: [
          departurePlacesProvider.overrideWith(
            (ref) => Stream.value(departurePlaces),
          ),
          tripsRepositoryProvider.overrideWithValue(repo),
          catalogProvider.overrideWith(
            (ref) => Stream.value(TravelCatalog(experiences: planned)),
          ),
          mapTilesEnabledProvider.overrideWithValue(false),
          itineraryJourneysProvider.overrideWith(
            (ref, key) async =>
                JourneySearchResult({'journeys': [], 'warnings': []}),
          ),
          transportDataProvider.overrideWith((ref, key) async => data),
          originTransportStopsProvider.overrideWith(
            (ref, origin) async => [
              TransportStop('a', {'name': origin}),
            ],
          ),
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
      final card = find.byKey(ValueKey(first.id));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      final sheet = tester.widget<ItineraryTransportSheet>(
        find.byType(ItineraryTransportSheet),
      );
      expect(sheet.from!.id, first.id);
      expect(sheet.to!.id, trip.originEndpointId);
      expect(sheet.index, planned.length);
      expect(sheet.segmentCount, planned.length + 1);
      final home = tester.widget<ItineraryEndpointCard>(
        find.byKey(const ValueKey('itinerary-home')),
      );
      expect(home.selected, false);
      expect(home.onTap, isNull);
      expect(find.byKey(const ValueKey('choose-outbound-1-2')), findsNothing);
      if (target == 'no-return') {
        expect(find.byKey(const ValueKey('choose-back-1-2')), findsNothing);
        await tester.drag(
          find.byKey(const ValueKey('transport-sheet-header')),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('候補を検索できませんでした。'), findsOneWidget);
      } else {
        final choose = find.byKey(const ValueKey('choose-back-1-2'));
        await tester.scrollUntilVisible(
          choose,
          100,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('transport-sheet-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await Scrollable.ensureVisible(tester.element(choose), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(choose);
        await tester.pumpAndSettle();
        final selected = container
            .read(tripProvider)
            .transportSelections
            .single;
        expect(selected.from, first.id);
        expect(selected.to, trip.originEndpointId);
        expect(selected.data['toKind'], 'origin');
        expect(selected.data['walkingMinutesAfter'], null);
        await container.read(tripLibraryProvider.notifier).flush();
        expect(
          (await repo.load())
              .activeTrip!
              .transportSelections
              .single
              .data['selectedTripId'],
          'back',
        );
        await tester.tap(find.byKey(const ValueKey('itinerary-view-booklet')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('saved-transport-back')),
          140,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('公共交通で移動 · 約30分'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('saved-transport-back')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _withBooklet(Widget editor) => Consumer(
  builder: (context, ref, child) => IndexedStack(
    index: ref.watch(appTabProvider) == AppTab.bookmark ? 1 : 0,
    children: [editor, const BookmarkHome()],
  ),
);
