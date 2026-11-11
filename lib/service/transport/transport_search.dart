import '../../model/transport_journey.dart';
import '../../model/stop_selection.dart';
import '../../model/transport.dart';

class TransportCandidate {
  final TransportTrip trip;
  final TransportRoute route;
  final AccessStop before, after;
  final StopTime boarding, alighting;
  final int? fare;
  final TransportJourney? journey;
  final String? boardingStopName, alightingStopName;
  String boardingLabel(String stopName) {
    final destination = (trip.data['headsign'] as String? ?? '').trim();
    return destination.isEmpty
        ? stopName
        : '$stopName／${transportDirection(destination)}';
  }

  bool get requiresLimitedExpress =>
      route.data['trainType'] == 'limited_express' ||
      route.data['requiresLimitedExpress'] == true ||
      (journey?.legs.any(
            (l) =>
                l['trainType'] == 'limited_express' ||
                l['requiresLimitedExpress'] == true,
          ) ??
          false);

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
    this.fare, {
    this.journey,
    this.boardingStopName,
    this.alightingStopName,
  });
}

List<TransportCandidate> findCandidates({
  required List<TransportTrip> trips,
  required List<TransportRoute> routes,
  required List<TransportService> services,
  required List<AccessStop> from,
  required List<AccessStop> to,
  List<TransportFare> fares = const [],
  DateTime? date,
  List<TransportStop> stops = const [],
}) {
  final result = <TransportCandidate>[];
  final stopNames = {for (final stop in stops) stop.id: stop.name};
  for (final trip in trips) {
    if (trip.data['isActive'] == false || trip.data['frequencyBased'] == true) {
      continue;
    }
    final route = routes.where((r) => r.id == trip.data['routeId']).firstOrNull;
    if (route == null || route.data['isActive'] == false) continue;
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
                      f.data['isActive'] != false &&
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
                fare?.data['amountYen'] as int? ??
                    resolveGtfsFare(
                      fares,
                      stops,
                      route.id,
                      start.stopId,
                      end.stopId,
                    ),
                boardingStopName:
                    stopNames[start.stopId] ?? a.data['stopName'] as String?,
                alightingStopName:
                    stopNames[end.stopId] ?? b.data['stopName'] as String?,
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

// Conservative fare-v1 resolution: uncertain zone/path or non-JPY fares remain unknown.
int? resolveGtfsFare(
  List<TransportFare> fares,
  List<TransportStop> stops,
  String routeId,
  String from,
  String to,
) {
  final origin = stops.where((s) => s.id == from).firstOrNull?.data['zoneId'];
  final destination = stops
      .where((s) => s.id == to)
      .firstOrNull
      ?.data['zoneId'];
  final prices = <int>{};
  for (final fare in fares) {
    if (fare.data['sourceType'] != 'gtfs' ||
        fare.data['currency'] != 'JPY' ||
        fare.data['containsUnresolved'] == true ||
        !routeId.startsWith('${fare.data['feedId']}~')) {
      continue;
    }
    final rules = fare.data['rules'] as List? ?? [];
    if (rules.isEmpty || rules.any((r) => (r as Map)['containsId'] != null)) {
      continue;
    }
    final matches = rules.any((raw) {
      final r = raw as Map;
      return (r['routeId'] == null || r['routeId'] == routeId) &&
          r['containsId'] == null &&
          (r['originId'] == null ||
              (origin != null && r['originId'] == origin)) &&
          (r['destinationId'] == null ||
              (destination != null && r['destinationId'] == destination));
    });
    final price = fare.data['price'];
    if (matches && price is num && price == price.roundToDouble()) {
      prices.add(price.toInt());
    }
  }
  return prices.length == 1 ? prices.single : null;
}
