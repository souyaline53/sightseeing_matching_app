import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/spot_visit_info.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/service/transport/transport_search.dart';
import 'package:sightseeing_matching_app/service/transport/itinerary_transport_options.dart';

void main() {
  test('arrival limit includes walking and seconds; 28:00 is allowed', () {
    TransportCandidate candidate(int seconds, int walk) => TransportCandidate(
      TransportTrip('t', {}),
      TransportRoute('r', {}),
      AccessStop({}),
      AccessStop({'walkingMinutes': walk}),
      StopTime({'departureMinutes': 1600}),
      StopTime({'arrivalMinutes': seconds ~/ 60, 'arrivalSeconds': seconds}),
      null,
    );
    expect(arrivesWithinServiceDay(candidate(28 * 3600, 0)), isTrue);
    expect(arrivesWithinServiceDay(candidate(28 * 3600 + 1, 0)), isFalse);
    expect(arrivesWithinServiceDay(candidate(28 * 3600 - 60, 2)), isFalse);
  });
  test('hours follow weekday and special hours, unknown stays blank', () {
    final day = DateTime(2026, 11, 16);
    expect(spotOpeningHoursLabel({}, day), isNull);
    final info = <String, dynamic>{
      'openingHoursStatus': 'scheduled',
      'openingHours': {
        'mon': [
          {'open': '09:00', 'close': '17:00'},
        ],
        'tue': [],
      },
    };
    expect(spotOpeningHoursLabel(info, day), '営業時間：09:00〜17:00');
    expect(spotOpeningHoursLabel(info, DateTime(2026, 11, 17)), '休業日');
    info['specialHours'] = [
      {
        'date': '2026-11-16',
        'hours': [
          {'open': '10:00', 'close': '12:00'},
        ],
      },
    ];
    expect(spotOpeningHoursLabel(info, day), '営業時間：10:00〜12:00');
    info['specialHours'] = [
      {'date': '2026-11-16', 'closed': true},
    ];
    expect(spotOpeningHoursLabel(info, day), '休業日');
    expect(
      spotOpeningHoursLabel({'openingHoursStatus': 'always_open'}, day),
      '営業時間：24時間',
    );
  });
}
