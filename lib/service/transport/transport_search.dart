import '../../model/transport.dart';

class TransportCandidate {
  final TransportTrip trip;
  final TransportRoute route;
  final AccessStop before, after;
  final StopTime boarding, alighting;
  final int? fare;
  String get status =>
      route.data['sourceType'] == 'sample' ||
          route.data['verificationStatus'] == 'sample'
      ? 'sample'
      : trip.status;
  TransportCandidate(
    this.trip,
    this.route,
    this.before,
    this.after,
    this.boarding,
    this.alighting,
    this.fare,
  );
}

List<TransportCandidate> findCandidates({
  required List<TransportTrip> trips,
  required List<TransportRoute> routes,
  required List<TransportService> services,
  required List<AccessStop> from,
  required List<AccessStop> to,
  List<TransportFare> fares = const [],
  DateTime? date,
}) {
  final result = <TransportCandidate>[];
  for (final trip in trips) {
    final route = routes.where((r) => r.id == trip.data['routeId']).firstOrNull;
    if (route == null) continue;
    if (date != null &&
        !services.any(
          (s) => s.id == trip.data['serviceId'] && s.operates(date),
        )) {
      continue;
    }
    for (final a in from) {
      for (final b in to) {
        for (final start in trip.times.where(
          (s) => s.stopId == a.stopId && s.pickup && s.departure != null,
        )) {
          for (final end in trip.times.where(
            (s) =>
                s.stopId == b.stopId &&
                s.dropoff &&
                s.arrival != null &&
                s.sequence > start.sequence &&
                s.arrival! >= start.departure!,
          )) {
            final fare = fares
                .where(
                  (f) =>
                      f.data['routeId'] == route.id &&
                      f.data['fromStopId'] == a.stopId &&
                      f.data['toStopId'] == b.stopId &&
                      f.data['fareType'] == 'adult',
                )
                .firstOrNull;
            result.add(
              TransportCandidate(
                trip,
                route,
                a,
                b,
                start,
                end,
                fare?.data['amountYen'] as int?,
              ),
            );
          }
        }
      }
    }
  }
  result.sort((a, b) => a.boarding.departure!.compareTo(b.boarding.departure!));
  return result;
}
