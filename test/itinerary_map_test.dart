import 'package:sightseeing_matching_app/model/trip_plan.dart' show TripLibrary;
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/screen/itinerary/widgets/itinerary_map_route.dart';
import 'package:latlong2/latlong.dart';
import 'departure_fixtures.dart';
import 'package:sightseeing_matching_app/data/departure_places.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/travel_catalog.dart';
import 'package:sightseeing_matching_app/screen/itinerary/widgets/itinerary_map.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'package:sightseeing_matching_app/widgets/departure_map.dart';

class _MemoryTrips implements TripsRepository {
  TripLibrary library;
  _MemoryTrips(this.library);
  @override
  Future<TripLibrary> load() async => library;
  @override
  Future<void> save(TripLibrary next) async {
    library = next;
  }
}

class _Trip extends TripNotifier {
  void replace(List<Experience> stops) => state = TripState(stops: stops);
  @override
  TripState build() => TripState(
    stops: [
      const Experience('a', '公園', '', '', '', '', '', '', 60),
      const Experience('b', '座標未設定', '', '', '', '', '', '', 60),
    ],
  );
}

void main() {
  testWidgets('map uses current catalog coordinates for saved legacy stops', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          departurePlacesProvider.overrideWith(
            (ref) => Stream.value(departurePlaces),
          ),
          tripProvider.overrideWith(_Trip.new),
          mapTilesEnabledProvider.overrideWithValue(false),
          catalogProvider.overrideWith(
            (ref) => Stream.value(
              TravelCatalog(
                experiences: [
                  const Experience(
                    'a',
                    '公園',
                    '',
                    '',
                    '',
                    '',
                    '',
                    '',
                    60,
                    address: '北海道夕張市高松7番地',
                    latitude: 43.065662,
                    longitude: 141.98732,
                  ),
                ],
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ItineraryMap(origin: '札幌駅')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final layer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    expect(layer.markers, hasLength(2));
    expect(layer.markers.last.point.latitude, 43.065662);
    expect(layer.markers.last.point.longitude, 141.98732);
    expect(find.text('出発・到着'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('位置未設定：2'), findsOneWidget);
    expect(
      tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines,
      hasLength(1),
    );
    expect(find.byTooltip('1. 公園\n北海道夕張市高松7番地'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'distinct arrival uses its own location and never reuses the origin when missing',
    () {
      final end = departurePlaces[2];
      final visits = itineraryMapVisits(
        '札幌駅',
        departurePlaces.first,
        [],
        destination: end.id,
        arrival: end,
      );
      expect(visits.last.label, '到着：${end.id}');
      expect(visits.last.point, end.point);
      expect(
        itineraryMapVisits(
          '札幌駅',
          departurePlaces.first,
          [],
          destination: '未登録',
        ).last.point,
        isNull,
      );
    },
  );
  test('visits preserve numbering, co-located endpoints and gaps', () {
    final visits = itineraryMapVisits('札幌駅', departurePlaces.first, [
      const Experience(
        'a',
        'A',
        '',
        '',
        '',
        '',
        '',
        '',
        60,
        latitude: 43,
        longitude: 142,
      ),
      const Experience('b', 'B', '', '', '', '', '', '', 60),
      const Experience(
        'c',
        'C',
        '',
        '',
        '',
        '',
        '',
        '',
        60,
        latitude: 44,
        longitude: 143,
      ),
    ]);
    expect(visits.map((v) => v.number), [null, 1, 2, 3, null]);
    expect(visits.last.label, '到着：札幌駅');
    expect(groupMapVisits(visits).first.map((v) => v.badge), ['出発', '到着']);
    expect(itineraryMapLegs(visits), hasLength(2));
    expect(validMapPoint(double.nan, 140), isNull);
    expect(validMapPoint(91, 140), isNull);
  });

  testWidgets(
    'auto fit keeps all pins within inner 80% above the sheet and refits after edits and resize',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer(
        overrides: [
          departurePlacesProvider.overrideWith(
            (ref) => Stream.value(departurePlaces),
          ),
          tripProvider.overrideWith(_Trip.new),
          mapTilesEnabledProvider.overrideWithValue(false),
          catalogProvider.overrideWith(
            (ref) => Stream.value(TravelCatalog(experiences: [])),
          ),
        ],
      );
      addTearDown(container.dispose);
      final stopA = const Experience(
        'a',
        'A',
        '',
        '',
        '',
        '',
        '',
        '',
        60,
        latitude: 41.8,
        longitude: 140.7,
      );
      final stopB = const Experience(
        'b',
        'B',
        '',
        '',
        '',
        '',
        '',
        '',
        60,
        latitude: 45.4,
        longitude: 141.7,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ItineraryMap(origin: '札幌駅', bottomInset: 160)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      (container.read(tripProvider.notifier) as _Trip).replace([stopA, stopB]);
      await tester.pumpAndSettle();
      void verify() {
        final widget = tester.widget<FlutterMap>(find.byType(FlutterMap));
        final camera = widget.mapController!.camera;
        final mapSize = tester.getSize(find.byType(FlutterMap));
        final visible = mapSize.height - 160;
        final markers = tester
            .widget<MarkerLayer>(find.byType(MarkerLayer))
            .markers;
        expect(markers, hasLength(3));
        for (final marker in markers) {
          final position = camera.latLngToScreenOffset(marker.point);
          expect(
            position.dx,
            inInclusiveRange(mapSize.width * .1, mapSize.width * .9),
          );
          expect(position.dy, inInclusiveRange(visible * .1, visible * .9));
        }
        expect(
          tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines,
          hasLength(3),
        );
      }

      verify();
      expect(find.text('出発・到着'), findsOneWidget);
      final lines = tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines;
      expect(lines.first.points, [
        departurePlaces.first.point,
        const LatLng(41.8, 140.7),
      ]);
      expect(lines.first.pattern.spacingFactor, 2.5);
      final cameraController = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      cameraController.move(const LatLng(43.2, 141.5), 9);
      await tester.pumpAndSettle();
      final centerBeforeReorder = cameraController.camera.center;
      final zoomBeforeReorder = cameraController.camera.zoom;
      (container.read(tripProvider.notifier) as _Trip).replace([stopB, stopA]);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .first
            .points
            .last,
        const LatLng(45.4, 141.7),
      );
      expect(cameraController.camera.center, centerBeforeReorder);
      expect(cameraController.camera.zoom, zoomBeforeReorder);
      await tester.binding.setSurfaceSize(const Size(350, 600));
      await tester.pumpAndSettle();
      verify();
      final map = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      map.move(const LatLng(0, 0), 2);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('旅程全体を表示'));
      await tester.pumpAndSettle();
      verify();
      for (final inset in [600.0, 160.0]) {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: ItineraryMap(origin: '札幌駅', bottomInset: inset),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
      verify();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'deleting visits renumbers shared-location pins using the real trip notifier',
    (tester) async {
      const a = Experience(
        'a',
        'A',
        '',
        '',
        '',
        '',
        '',
        '',
        60,
        latitude: 43.1,
        longitude: 142,
      );
      const b = Experience(
        'b',
        'B',
        '',
        '',
        '',
        '',
        '',
        '',
        60,
        latitude: 43.1,
        longitude: 142,
      );
      const c = Experience(
        'c',
        'C',
        '',
        '',
        '',
        '',
        '',
        '',
        60,
        latitude: 43.1,
        longitude: 142,
      );
      final plan = TripState(stops: const [a, b, c], saved: const [a, b, c]);
      final repository = _MemoryTrips(
        TripLibrary(plans: [plan], activeId: plan.id),
      );
      final container = ProviderContainer(
        overrides: [
          tripsRepositoryProvider.overrideWithValue(repository),
          departurePlacesProvider.overrideWith(
            (ref) => Stream.value(departurePlaces),
          ),
          mapTilesEnabledProvider.overrideWithValue(false),
          catalogProvider.overrideWith(
            (ref) => Stream.value(TravelCatalog(experiences: const [a, b, c])),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(tripLibraryProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ItineraryMap(origin: '札幌駅')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('出発・到着'), findsOneWidget);
      expect(find.text('1・2・3'), findsOneWidget);
      container.read(tripProvider.notifier).removeStop(b);
      await tester.pumpAndSettle();
      expect(find.text('1・2・3'), findsNothing);
      expect(find.text('1・2'), findsOneWidget);
      expect(find.byTooltip('1. A\n2. C'), findsOneWidget);
      container.read(tripProvider.notifier).removeStop(a);
      await tester.pumpAndSettle();
      expect(find.text('1・2'), findsNothing);
      expect(find.text('1'), findsOneWidget);
      expect(find.byTooltip('1. C'), findsOneWidget);
      container.read(tripProvider.notifier).removeStop(c);
      await tester.pumpAndSettle();
      expect(find.text('1'), findsNothing);
      expect(find.text('出発・到着'), findsOneWidget);
      await container.read(tripLibraryProvider.notifier).flush();
      expect(repository.library.activeTrip!.stops, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
