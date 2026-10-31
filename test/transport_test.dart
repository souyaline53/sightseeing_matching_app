import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/service/transport/transport_search.dart';
import 'test_support.dart';

void main() {
  final service = TransportService('s', {
    'timezone': 'Asia/Tokyo',
    'validFrom': '2026-01-01',
    'validTo': '2026-12-31',
    'weekdays': [1, 2, 3, 4, 5],
    'addedDates': ['2026-11-01'],
    'removedDates': ['2026-11-02'],
  });
  final trip = TransportTrip('trip', {
    'routeId': 'r',
    'serviceId': 's',
    'verificationStatus': 'sample',
    'stopTimes': [
      {
        'stopId': 'd',
        'sequence': 4,
        'arrivalMinutes': 1530,
        'departureMinutes': null,
      },
      {
        'stopId': 'b',
        'sequence': 2,
        'arrivalMinutes': 1490,
        'departureMinutes': 1492,
      },
      {
        'stopId': 'a',
        'sequence': 1,
        'arrivalMinutes': null,
        'departureMinutes': 1480,
      },
      {
        'stopId': 'c',
        'sequence': 3,
        'arrivalMinutes': 1510,
        'departureMinutes': 1512,
      },
    ],
  });
  List<TransportCandidate> search(String a, String b, {DateTime? date}) =>
      findCandidates(
        trips: [trip],
        routes: [
          TransportRoute('r', {'name': '架空路線'}),
        ],
        services: [service],
        from: [
          AccessStop({'stopId': a, 'walkingMinutes': null}),
        ],
        to: [
          AccessStop({'stopId': b, 'walkingMinutes': 8}),
        ],
        date: date,
      );
  test(
    'sequence and intermediate boarding/alighting; missing endpoint times',
    () {
      final c = search('b', 'c').single;
      expect(c.boarding.departure, 1492);
      expect(c.alighting.arrival, 1510);
      expect(c.before.walkingMinutes, isNull);
      expect(c.fare, isNull);
      expect(search('c', 'b'), isEmpty);
      expect(search('a', 'd'), hasLength(1));
      expect(trip.times.map((t) => t.sequence), [1, 2, 3, 4]);
    },
  );
  test('after midnight retains service day hours', () {
    expect(transportTime(1510), '25:10');
    expect(transportTime(null), '—');
  });
  test('calendar weekdays, weekend and exceptions', () {
    expect(service.operates(DateTime(2026, 10, 30)), isTrue);
    expect(service.operates(DateTime(2026, 10, 31)), isFalse);
    expect(service.operates(DateTime(2026, 11, 1)), isTrue);
    expect(service.operates(DateTime(2026, 11, 2)), isFalse);
    expect(service.operates(DateTime(2027, 1, 1)), isFalse);
    expect(search('b', 'c', date: DateTime(2026, 10, 31)), isEmpty);
    expect(search('b', 'c'), hasLength(1));
  });
  test('no access stops and no registered trip', () {
    expect(
      findCandidates(trips: [trip], routes: [], services: [], from: [], to: []),
      isEmpty,
    );
    expect(search('unknown', 'c'), isEmpty);
  });
  const a = Experience('a', 'A', '', '', '', '', '', '', 60);
  const b = Experience('b', 'B', '', '', '', '', '', '', 60);
  const c = Experience('c', 'C', '', '', '', '', '', '', 60);
  final selection = TransportSelection({
    'fromSpotId': 'a',
    'toSpotId': 'b',
    'selectedTripId': 'trip',
    'walkingMinutesBefore': null,
    'departureMinutes': 1492,
  });
  test('reordered segments do not inherit another segment selection', () {
    final plan = TripState(stops: [a, b, c], transportSelections: [selection]);
    expect(plan.copyWith(stops: [a, c, b]).transportSelections, isEmpty);
    expect(plan.copyWith(stops: [b, a, c]).transportSelections, isEmpty);
  });
  test('legacy experience and plan JSON stay compatible', () {
    final json = a.toJson()..remove('accessStops');
    expect(Experience.fromJson(json).accessStops, isEmpty);
    final plan = TripState(stops: [a, b]).toJson()
      ..remove('transportSelections')
      ..remove('stayMinutes');
    expect(TripState.fromJson(plan).transportSelections, isEmpty);
  });
  test('selected trip and unknown walking survive persistent reload', () async {
    final repo = LocalTripsRepository(storage: MemorySettingsStorage());
    final p = TripState(
      stops: [a, b],
      transportSelections: [selection],
      stayMinutes: {'a': 90},
    );
    await repo.save(TripLibrary(plans: [p]));
    final restored = (await repo.load()).activeTrip!;
    expect(restored.transportSelections.single.data, selection.data);
    expect(restored.stayMinutes['a'], 90);
    expect(restored.travelDate, isNull);
    expect(jsonEncode(restored.toJson()), contains('selectedTripId'));
  });
}
