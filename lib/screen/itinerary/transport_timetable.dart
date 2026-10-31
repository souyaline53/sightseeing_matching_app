import 'package:flutter/material.dart';
import '../../model/transport.dart';
import '../../repository/transport_repository.dart';

class TransportTimetable extends StatelessWidget {
  final TransportTrip trip;
  final TransportData data;
  final bool initiallyExpanded;
  const TransportTimetable({
    super.key,
    required this.trip,
    required this.data,
    this.initiallyExpanded = false,
  });
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('途中駅・バス停の時刻表'),
    initiallyExpanded: initiallyExpanded,
    children: [
      Table(
        columnWidths: const {0: FlexColumnWidth(2)},
        children: [
          const TableRow(children: [Text('停留所'), Text('到着'), Text('出発')]),
          for (final t in trip.times)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '${data.stopName(t.stopId)}${t.pickup ? '' : '（乗車不可）'}${t.dropoff ? '' : '（降車不可）'}',
                  ),
                ),
                Text(transportTime(t.arrival)),
                Text(transportTime(t.departure)),
              ],
            ),
        ],
      ),
    ],
  );
}
