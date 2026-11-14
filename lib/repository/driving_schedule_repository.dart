import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/experience.dart';
import '../model/transport.dart';
import '../service/transport/driving_schedule.dart';
import '../state/trip_state.dart';
import 'driving_route_repository.dart';

String drivingScheduleKey(TripState trip, List<Experience> points) =>
    jsonEncode({
      'date': drivingServiceDate(trip),
      'departureMinutes': trip.departureMinutes,
      'points': points
          .map(
            (point) => {
              'id': point.id,
              ...drivingEndpoint(point),
              'stayMinutes': trip.stayMinutes[point.id] ?? point.minutes,
            },
          )
          .toList(),
      'overrides': [
        for (final selection in trip.transportSelections)
          if (isCurrentDrivingSelection(trip, selection) &&
              selection.data['departureOverride'] != false)
            {
              'from': selection.from,
              'to': selection.to,
              'minutes':
                  selection.data['requestedDepartureMinutes'] ??
                  selection.data['departureMinutes'],
            },
      ],
    });

final drivingScheduleProvider =
    FutureProvider.family<List<TransportSelection>, String>((ref, key) async {
      final input = Map<String, dynamic>.from(jsonDecode(key) as Map);
      final points = (input['points'] as List).cast<Map>();
      final futures = [
        for (var i = 0; i < points.length - 1; i++)
          ref.watch(
            drivingRouteProvider(
              jsonEncode({
                'from': {
                  for (final field in [
                    'name',
                    'address',
                    'latitude',
                    'longitude',
                  ])
                    field: points[i][field],
                },
                'to': {
                  for (final field in [
                    'name',
                    'address',
                    'latitude',
                    'longitude',
                  ])
                    field: points[i + 1][field],
                },
              }),
            ).future,
          ),
      ];
      final routes = await Future.wait(futures);
      var earliest = input['departureMinutes'] as int;
      final result = <TransportSelection>[];
      for (var i = 0; i < routes.length; i++) {
        final from = points[i], to = points[i + 1], route = routes[i];
        final override = (input['overrides'] as List)
            .cast<Map>()
            .where((row) => row['from'] == from['id'] && row['to'] == to['id'])
            .firstOrNull;
        final requested = override?['minutes'] as int?;
        final departure = requested != null && (i == 0 || requested > earliest)
            ? requested
            : earliest;
        final duration = ((route['durationSeconds'] as num) / 60).ceil();
        final arrival = departure + duration;
        result.add(
          TransportSelection({
            'mode': 'car',
            if (route['walkingOnly'] == true) 'walkingOnly': true,
            'fromSpotId': from['id'],
            'toSpotId': to['id'],
            'selectedTripId': "car-${from['id']}-${to['id']}",
            'departureMinutes': departure,
            'arrivalMinutes': arrival,
            'durationSeconds': route['durationSeconds'],
            'distanceMeters': route['distanceMeters'],
            'provider': route['provider'],
            'serviceDate': input['date'],
            'departureOverride': override != null,
            'requestedDepartureMinutes': ?requested,
          }),
        );
        earliest = arrival + (to['stayMinutes'] as int);
      }
      return result;
    });

void listenToDrivingSchedule(
  WidgetRef ref,
  TripState trip,
  List<Experience> points,
) {
  if (trip.publicTransport ||
      points.length < 3 ||
      !points.every(hasDrivingLocation)) {
    return;
  }
  final key = drivingScheduleKey(trip, points);
  final schedule = ref.watch(drivingScheduleProvider(key));
  final selections = schedule.value;
  if (selections == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!ref.context.mounted) return;
    final current = ref.read(tripProvider);
    if (current.id != trip.id ||
        current.publicTransport ||
        drivingScheduleKey(current, points) != key) {
      return;
    }
    ref.read(tripProvider.notifier).syncCarTransport(selections);
  });
}
