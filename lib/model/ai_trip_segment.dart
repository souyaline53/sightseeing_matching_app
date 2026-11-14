import 'transport.dart';
import 'trip_plan.dart';

int? _seconds(Object? v) => v is int && v >= 0 ? v : null;
String? _id(Object? v) => v is String
    ? v
    : v is Map
    ? (v['spotId'] ?? v['placeId'] ?? v['id']) as String?
    : null;
List<Json> _maps(Object? v) => v is List
    ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : [];

class AiTripSegment {
  final String fromId, toId, fromName, toName;
  final int? departureSeconds, arrivalSeconds;
  final List<Json> steps;
  final Map<String, String> names, routeAgencies;
  final bool requiresReview;
  final List<String> reviewReasons;
  const AiTripSegment({
    required this.fromId,
    required this.toId,
    required this.fromName,
    required this.toName,
    required this.departureSeconds,
    required this.arrivalSeconds,
    required this.steps,
    required this.names,
    this.routeAgencies = const {},
    required this.requiresReview,
    this.reviewReasons = const [],
  });
  bool get walkingOnly =>
      steps.isNotEmpty && steps.every((s) => s['kind'] == 'walk');
  String label(Object? id, [String fallback = '名称未提供']) =>
      names[id] ?? fallback;
  String? routeLabel(Json step) {
    final route = step['routeName'] as String? ?? names[step['routeId']];
    final agency =
        step['agencyName'] as String? ??
        names[step['agencyId']] ??
        routeAgencies[step['routeId']];
    final labels = <String>[?agency, ?route];
    return labels.isEmpty ? null : labels.join(' · ');
  }

  String get routeNames =>
      steps.map(routeLabel).whereType<String>().toSet().join('・');
}

/// Project the original response onto adjacent places without inventing services.
/// Supports explicit place legs and flat timed steps. Unknown boundaries stay empty.
List<AiTripSegment> aiTripSegments(TripState trip) {
  final result = trip.ai['result'];
  if (result is! Map || result['itinerary'] is! Map) return [];
  final itinerary = result['itinerary'] as Map;
  final metadata = result['aiMetadata'] as Map? ?? {};
  final lookup = metadata['lookup'] as Map? ?? {};
  final names = <String, String>{};
  for (final rows in lookup.values) {
    for (final row in _maps(rows)) {
      if (row['id'] is String && row['name'] is String) {
        names[row['id'] as String] = row['name'] as String;
      }
    }
  }
  final routeAgencies = <String, String>{
    for (final route in _maps(lookup['routes']))
      if (route['id'] is String && names[route['agencyId']] != null)
        route['id'] as String: names[route['agencyId']]!,
  };
  final config = trip.ai['config'] as Map? ?? {};
  final points = [
    (trip.originEndpointId, trip.origin),
    ...trip.stops.map((s) => (s.id, s.displayName)),
    (trip.destinationEndpointId, trip.arrivalPlace),
  ];
  final visits = {
    for (final v in _maps(itinerary['visits']))
      if (_id(v) != null) _id(v)!: v,
  };
  final summary = itinerary['summary'] as Map? ?? {};
  final legs = _maps(itinerary['legs']);
  final hasPlaceLegs = legs.any(
    (l) =>
        l.containsKey('fromPlaceId') ||
        l.containsKey('fromSpotId') ||
        l.containsKey('from'),
  );
  final flat = <Json>[];
  for (final leg in legs) {
    final children = _maps(leg['steps']);
    if (children.isEmpty) {
      flat.add(leg);
    } else {
      flat.addAll(children);
    }
  }
  if (legs.isEmpty) flat.addAll(_maps(itinerary['steps']));
  int? departureOf(Json s) =>
      _seconds(s['departureSeconds'] ?? s['startSeconds']);
  int? arrivalOf(Json s) => _seconds(s['arrivalSeconds'] ?? s['endSeconds']);
  bool same(Object? value, String id, int pointIndex) {
    final candidate = _id(value);
    if (candidate == id) return true;
    if (pointIndex == 0) {
      return candidate == _id(config['origin']) || candidate == trip.origin;
    }
    if (pointIndex == points.length - 1) {
      return candidate == _id(config['destination']) ||
          candidate == trip.arrivalPlace;
    }
    return false;
  }

  final segments = <AiTripSegment>[];
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i], b = points[i + 1];
    final start = i == 0
        ? _seconds(
            summary['departureSeconds'] ??
                itinerary['departureSeconds'] ??
                config['departureSeconds'],
          )
        : _seconds(visits[a.$1]?['departureSeconds']);
    final end = i == points.length - 2
        ? _seconds(summary['arrivalSeconds'] ?? itinerary['arrivalSeconds'])
        : _seconds(visits[b.$1]?['arrivalSeconds']);
    final explicit = legs
        .where(
          (l) =>
              same(l['fromPlaceId'] ?? l['fromSpotId'] ?? l['from'], a.$1, i) &&
              same(l['toPlaceId'] ?? l['toSpotId'] ?? l['to'], b.$1, i + 1),
        )
        .toList();
    final steps = <Json>[];
    if (explicit.isNotEmpty) {
      for (final l in explicit) {
        final children = _maps(l['steps']);
        steps.addAll(children.isEmpty ? [l] : children);
      }
    } else if (!hasPlaceLegs && start != null && end != null) {
      steps.addAll(
        flat.where((s) {
          final d = departureOf(s), r = arrivalOf(s);
          return d != null && r != null && d >= start && r <= end && r >= d;
        }),
      );
    }
    final visible = steps
        .where((s) => s['kind'] != 'visit' && s['kind'] != 'stay')
        .toList();
    final departures = visible.map(departureOf).whereType<int>().toList()
      ..sort();
    final arrivals = visible.map(arrivalOf).whereType<int>().toList()..sort();
    final firstExplicit = explicit.firstOrNull,
        lastExplicit = explicit.lastOrNull;
    final departure =
        _seconds(firstExplicit?['departureSeconds']) ?? departures.firstOrNull;
    final arrival =
        _seconds(lastExplicit?['arrivalSeconds']) ?? arrivals.lastOrNull;
    segments.add(
      AiTripSegment(
        fromId: a.$1,
        toId: b.$1,
        fromName: a.$2,
        toName: b.$2,
        departureSeconds: departure,
        arrivalSeconds: arrival,
        steps: visible,
        names: names,
        routeAgencies: routeAgencies,
        requiresReview: itinerary['requiresReview'] != false,
        reviewReasons: (itinerary['reviewReasons'] as List? ?? [])
            .map((r) => r.toString())
            .toList(),
      ),
    );
  }
  return segments;
}

AiTripSegment? activeAiTripSegment(TripState trip, String from, String to) {
  if (!trip.publicTransport) return null;
  if (!trip.aiProposalValid ||
      trip.ai['enabled'] == false ||
      trip.transportSelections.any((s) => s.from == from && s.to == to)) {
    return null;
  }
  return aiTripSegments(trip)
      .where((s) => s.fromId == from && s.toId == to && s.steps.isNotEmpty)
      .firstOrNull;
}
