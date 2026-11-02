import '../../model/trip_plan.dart';
import '../../model/transport.dart';
import '../../model/transport_journey.dart';
import 'transport_search.dart';

bool sharesAccessStop(List<AccessStop> from, List<AccessStop> to) {
  final ids = from
      .where((s) => s.data['isActive'] != false && s.stopId.isNotEmpty)
      .map((s) => s.stopId)
      .toSet();
  return to.any((s) => s.data['isActive'] != false && ids.contains(s.stopId));
}

TransportCandidate journeyCandidate(TransportJourney journey) {
  final legs = journey.legs, first = legs.first, last = legs.last;
  final tripId = legs.length == 1 ? first['tripId'] as String : journey.id;
  final boarding = StopTime({
    'stopId': first['boardingStopId'],
    'sequence': first['boardingSequence'],
    'departureMinutes': (first['departureSeconds'] as int) ~/ 60,
    'departureSeconds': first['departureSeconds'],
  });
  final alighting = StopTime({
    'stopId': last['alightingStopId'],
    'sequence': last['alightingSequence'],
    'arrivalMinutes': (last['arrivalSeconds'] as int) ~/ 60,
    'arrivalSeconds': last['arrivalSeconds'],
  });
  return TransportCandidate(
    TransportTrip(tripId, {
      'routeId': first['routeId'],
      'headsign': legs.length == 1
          ? first['headsign']
          : '${journey.transferCount}回乗換',
      'verificationStatus': journey.data['verificationStatus'],
      'versionId': first['versionId'],
      'stopTimes': [boarding.data, alighting.data],
    }),
    TransportRoute(first['routeId'] as String, {
      'name': legs.map((l) => l['routeName']).join(' → '),
    }),
    AccessStop({
      'stopId': boarding.stopId,
      'walkingMinutes': journey.data['walkingMinutesBefore'],
    }),
    AccessStop({
      'stopId': alighting.stopId,
      'walkingMinutes': journey.data['walkingMinutesAfter'],
    }),
    boarding,
    alighting,
    legs.length == 1 ? first['fareYen'] as int? : null,
    journey: journey,
    boardingStopName: first['boardingStopName'] as String?,
    alightingStopName: last['alightingStopName'] as String?,
  );
}

int candidateDepartureSeconds(TransportCandidate candidate) =>
    candidate.journey?.data['departureFromSpotSeconds'] as int? ??
    (candidate.boarding.data['departureSeconds'] as int? ??
            candidate.boarding.departure! * 60) -
        (candidate.before.walkingMinutes ?? 0) * 60;

int segmentEarliestDeparture(
  TripState trip,
  String? fromId, {
  bool? previousWalkingOnly,
}) {
  final base = trip.departureMinutes * 60;
  final index = trip.stops.indexWhere((s) => s.id == fromId);
  if (index < 0) return base;
  if (previousWalkingOnly ??
      (index > 0 &&
          sharesAccessStop(
            trip.stops[index - 1].accessStops,
            trip.stops[index].accessStops,
          ))) {
    return base;
  }
  final precedingId = index == 0
      ? trip.originEndpointId
      : trip.stops[index - 1].id;
  final selected = trip.transportSelections
      .where((s) => s.from == precedingId && s.to == fromId)
      .firstOrNull;
  if (selected == null) return base;
  final date = trip.travelDate;
  if (date != null) {
    final expected =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (!(selected.data['serviceDate'] as String? ?? '').startsWith(expected)) {
      return base;
    }
  }
  final journey = selected.data['journey'] as Map?;
  final arrival =
      journey?['arrivalSeconds'] as int? ??
      (selected.data['arrivalSeconds'] as int? ??
              (selected.data['arrivalMinutes'] as int? ?? 0) * 60) +
          (selected.data['walkingMinutesAfter'] as int? ?? 0) * 60;
  return arrival > base ? arrival : base;
}
