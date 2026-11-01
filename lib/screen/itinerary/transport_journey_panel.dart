import 'package:flutter/material.dart';
import '../../model/transport_journey.dart';

// Shared by timetable details and the saved booklet. Technical IDs remain in saved data only.
class TransportJourneyDetails extends StatelessWidget {
  final TransportJourney journey;
  const TransportJourneyDetails({super.key, required this.journey});
  @override
  Widget build(BuildContext context) {
    final legs = journey.legs, transfers = journey.transfers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${journeyTime(journey.data['departureSeconds'] as int)} 発 → ${journeyTime(legs.last['arrivalSeconds'] as int)} 着${journey.transferCount == 0 ? '' : '／${journey.transferCount}回乗換'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        if (journey.data['walkingMinutesBefore'] case final int minutes)
          Text('乗車前 徒歩$minutes分'),
        for (var i = 0; i < legs.length; i++) ...[
          const Divider(),
          Text(
            '${legs[i]['routeName']} ${legs[i]['headsign']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            '${journeyTime(legs[i]['departureSeconds'] as int)} ${legs[i]['boardingStopName']}${legs[i]['boardingPlatformCode'] == null ? '' : '（${legs[i]['boardingPlatformCode']}番）'} → ${journeyTime(legs[i]['arrivalSeconds'] as int)} ${legs[i]['alightingStopName']}',
          ),
          if (i < transfers.length &&
              transfers[i]['fromStopId'] != transfers[i]['toStopId'])
            Text(
              '↓ 乗換の移動 約${((transfers[i]['requiredSeconds'] as int) / 60).ceil()}分',
            ),
        ],
        if (journey.data['walkingMinutesAfter'] case final int minutes)
          Text('降車後 徒歩$minutes分'),
      ],
    );
  }
}
