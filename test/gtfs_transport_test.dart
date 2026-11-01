import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/service/transport/transport_search.dart';

void main() {
  final stops = [
    TransportStop('f~a', {'zoneId': 'A'}),
    TransportStop('f~b', {'zoneId': 'B'}),
  ];
  TransportFare fare(
    String id,
    int price, {
    String? contains,
    String feed = 'f',
  }) => TransportFare(id, {
    'feedId': feed,
    'sourceType': 'gtfs',
    'currency': 'JPY',
    'price': price,
    'rules': [
      {
        'routeId': 'f~r',
        'originId': 'A',
        'destinationId': 'B',
        'containsId': contains,
      },
    ],
  });
  test(
    'zone fare is directional; conflicting prices, contains zones, other feeds and passes remain unknown',
    () {
      expect(
        resolveGtfsFare([fare('x', 500)], stops, 'f~r', 'f~a', 'f~b'),
        500,
      );
      expect(
        resolveGtfsFare([fare('x', 500)], stops, 'f~r', 'f~b', 'f~a'),
        isNull,
      );
      expect(
        resolveGtfsFare(
          [fare('x', 500), fare('y', 600)],
          stops,
          'f~r',
          'f~a',
          'f~b',
        ),
        isNull,
      );
      expect(
        resolveGtfsFare(
          [fare('x', 500, contains: 'C')],
          stops,
          'f~r',
          'f~a',
          'f~b',
        ),
        isNull,
      );
      expect(
        resolveGtfsFare(
          [fare('x', 500, feed: 'other')],
          stops,
          'f~r',
          'f~a',
          'f~b',
        ),
        isNull,
      );
    },
  );
  test(
    'repeated stop visits are distinguished by sequence; restricted pickup and dropoff excluded',
    () {
      final trip = TransportTrip('t', {
        'routeId': 'r',
        'stopTimes': [
          {
            'stopId': 'a',
            'sequence': 0,
            'departureMinutes': 600,
            'pickupType': 1,
          },
          {
            'stopId': 'b',
            'sequence': 1,
            'arrivalMinutes': 610,
            'dropOffType': 0,
          },
          {
            'stopId': 'a',
            'sequence': 2,
            'departureMinutes': 620,
            'pickupType': 0,
          },
          {
            'stopId': 'b',
            'sequence': 3,
            'arrivalMinutes': 630,
            'dropOffType': 0,
          },
        ],
      });
      final result = findCandidates(
        trips: [trip],
        routes: [TransportRoute('r', {})],
        services: [],
        from: [
          AccessStop({'stopId': 'a'}),
        ],
        to: [
          AccessStop({'stopId': 'b'}),
        ],
      );
      expect(result.length, 1);
      expect(result.single.boarding.sequence, 2);
      expect(result.single.alighting.sequence, 3);
      expect(
        StopTime({'stopId': 'a', 'sequence': 1, 'pickupType': 2}).pickup,
        false,
      );
    },
  );
}
