import '../../model/trip_plan.dart';
import '../../model/transport.dart';

String drivingServiceDate(TripState trip) =>
    '${trip.date.year.toString().padLeft(4, '0')}-${trip.date.month.toString().padLeft(2, '0')}-${trip.date.day.toString().padLeft(2, '0')}';

bool isCurrentDrivingSelection(TripState trip, TransportSelection selection) =>
    selection.data['mode'] == 'car' &&
    selection.data['serviceDate'] == drivingServiceDate(trip);

int drivingEarliestDepartureMinutes(TripState trip, String fromId) {
  final index = trip.stops.indexWhere((spot) => spot.id == fromId);
  if (index < 0) return trip.departureMinutes;
  final previousId = index == 0
      ? trip.originEndpointId
      : trip.stops[index - 1].id;
  final previous = trip.transportSelections
      .where(
        (selection) =>
            selection.from == previousId &&
            selection.to == fromId &&
            isCurrentDrivingSelection(trip, selection),
      )
      .firstOrNull;
  final arrival =
      previous?.data['arrivalMinutes'] as int? ?? trip.departureMinutes;
  final stay = trip.stayMinutes[fromId] ?? trip.stops[index].minutes;
  return arrival + stay;
}

String drivingTime(int? minutes) {
  if (minutes == null) return '—';
  final days = minutes ~/ 1440;
  final clock =
      '${minutes % 1440 ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
  final prefix = days == 0
      ? ''
      : days == 1
      ? '翌日'
      : '$days日後';
  return '$prefix$clock';
}
