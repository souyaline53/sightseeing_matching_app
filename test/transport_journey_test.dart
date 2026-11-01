import 'package:archive/archive.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/model/transport_journey.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/screen/itinerary/transport_journey_panel.dart';

Json resultFixture() => {
  'journeys': [
    {
      'id': 'journey',
      'queryDate': '2026-06-01',
      'transferCount': 1,
      'departureSeconds': 28801,
      'arrivalSeconds': 32400,
      'walkingMinutesBefore': null,
      'walkingMinutesAfter': 10,
      'verificationStatus': 'needsReview',
      'legs': [
        for (var i = 0; i < 2; i++)
          {
            'tripId': 'trip$i',
            'routeId': 'route$i',
            'routeName': '路線$i',
            'headsign': '行先$i',
            'boardingStopId': 'platform$i',
            'boardingStopName': '同名',
            'boardingPlatformCode': '$i',
            'alightingStopId': 'platform${i + 1}',
            'alightingStopName': '同名',
            'departureSeconds': 28801 + i * 1800,
            'arrivalSeconds': 30000 + i * 1800,
            'boardingSequence': 2,
            'alightingSequence': 5,
            'serviceDate': '2026-06-01',
            'versionId': 'v$i',
          },
      ],
      'transfers': [
        {
          'fromStopId': 'platform1',
          'toStopId': 'platform1',
          'requiredSeconds': 180,
          'availableSeconds': 601,
          'source': 'same_stop',
        },
      ],
    },
  ],
  'warnings': ['同名だけでは接続しません'],
};
void main() {
  test(
    'journey snapshot survives JSON save/load and date changes flag review',
    () {
      final journey = JourneySearchResult(resultFixture()).journeys.single;
      Experience spot(String id) => Experience.fromJson({
        ...const Experience('', '', '', '', '', '', '', '', 60).toJson(),
        'id': id,
      });
      final trip = TripState(
        stops: [spot('a'), spot('b')],
        travelDate: DateTime(2026, 6, 1),
        transportSelections: [journey.selection('a', 'b')],
      );
      final loaded = TripState.fromJson(
        jsonDecode(jsonEncode(trip.toJson())) as Json,
      );
      expect(loaded.transportSelections.single.data['journey'], journey.data);
      expect(
        loaded.transportSelections.single.data['walkingMinutesBefore'],
        isNull,
      );
      final changed = loaded.copyWith(travelDate: DateTime(2026, 6, 2));
      expect(
        changed.transportSelections.single.data['verificationStatus'],
        'needsReview',
      );
      expect(changed.transportSelections.single.data['serviceDate'], isNull);
      expect(changed.transportSelections.single.data['journey'], journey.data);
      final legacy = TransportSelection({
        'fromSpotId': 'a',
        'toSpotId': 'b',
        'selectedTripId': 'legacy',
      });
      expect(
        TripState.fromJson(
          TripState(transportSelections: [legacy]).toJson(),
        ).transportSelections.single.toJson(),
        legacy.toJson(),
      );
      expect(journeyTime(90001), '1日後 01:00:01');
    },
  );
  test(
    'compressed timetable pool decodes with legacy response compatibility',
    () {
      final rows = resultFixture()['journeys'];
      final bytes = utf8.encode(jsonEncode(rows));
      final response = {
        'journeyPool': {
          'encoding': 'gzip+base64',
          'rawBytes': bytes.length,
          'data': base64Encode(GZipEncoder().encode(bytes)),
        },
        'warnings': <String>[],
      };
      final decoded = JourneySearchResult(response);
      expect(decoded.journeys.single.legs.length, 2);
      expect(
        decoded.journeys.single.data,
        JourneySearchResult(resultFixture()).journeys.single.data,
      );
    },
  );
  testWidgets(
    'details show names and known walks without technical IDs or unknown-walk warnings',
    (tester) async {
      final journey = JourneySearchResult(resultFixture()).journeys.single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TransportJourneyDetails(journey: journey),
            ),
          ),
        ),
      );
      expect(find.textContaining('乗場ID'), findsNothing);
      expect(find.textContaining('trip0'), findsNothing);
      expect(find.textContaining('platform0'), findsNothing);
      expect(find.textContaining('徒歩時間が未登録'), findsNothing);
      expect(find.textContaining('徒歩10分'), findsOneWidget);
      expect(find.textContaining('路線0'), findsOneWidget);
    },
  );
}
