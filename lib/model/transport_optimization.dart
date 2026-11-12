import 'transport.dart';

/// Seconds are relative to midnight on [date] in Asia/Tokyo, including >24h.
class OptimizationPlace {
  final String id, name;
  final double? latitude, longitude;
  final List<AccessStop> accessStops;
  const OptimizationPlace({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
    this.accessStops = const [],
  });
  Json toJson() => {
    'id': id,
    'name': name,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    'accessStops': accessStops.map((s) => s.toJson()).toList(),
  };
}

/// Opening windows must be resolved for the requested date, including exceptions.
/// unknown never means open; closed has no windows.
class OptimizationVisit {
  final OptimizationPlace place;
  final int staySeconds;
  final String openingStatus;
  final List<(int, int)> openingWindows;
  const OptimizationVisit({
    required this.place,
    required this.staySeconds,
    this.openingStatus = 'unknown',
    this.openingWindows = const [],
  });
  Json toJson() => {
    ...place.toJson(),
    'staySeconds': staySeconds,
    'opening': {
      'status': openingStatus,
      'windows': openingWindows.map((w) => [w.$1, w.$2]).toList(),
    },
  };
}

class TransportOptimizationInput {
  final String date;
  final OptimizationPlace origin, destination;
  final int departureSeconds, deadlineSeconds, minimumTransferSeconds;
  final List<OptimizationVisit> visits;
  final List<String> modes;
  final String preference;
  const TransportOptimizationInput({
    required this.date,
    required this.origin,
    required this.destination,
    required this.departureSeconds,
    required this.deadlineSeconds,
    required this.visits,
    this.minimumTransferSeconds = 180,
    this.modes = const ['rail', 'bus', 'walk'],
    this.preference = 'travel_time',
  });
  Json toJson() => {
    'date': date,
    'origin': origin.toJson(),
    'destination': destination.toJson(),
    'departureSeconds': departureSeconds,
    'deadlineSeconds': deadlineSeconds,
    'minimumTransferSeconds': minimumTransferSeconds,
    'visits': visits.map((v) => v.toJson()).toList(),
    'modes': modes,
    'preference': preference,
  };
}

class PreparedTransportOptimization {
  final String transportJson;
  final int bytes;
  PreparedTransportOptimization.fromJson(Json data)
    : transportJson = (data['inputs'] as Map)['transport_json'] as String,
      bytes = data['bytes'] as int;
}

/// Future workflow output contract. Never applies unvalidated legs to TripState.
class TransportOptimizationResult {
  final String status;
  final List<Json> candidates;
  final String? selectedCandidateId;
  TransportOptimizationResult.fromJson(Json data)
    : status = data['status'] as String,
      candidates = (data['candidates'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList(),
      selectedCandidateId = data['selectedCandidateId'] as String? {
    if (!['feasible', 'infeasible', 'needs_review'].contains(status) ||
        (status == 'infeasible' && candidates.isNotEmpty) ||
        (status == 'feasible' &&
            (candidates.isEmpty ||
                !candidates.any((c) => c['id'] == selectedCandidateId)))) {
      throw const FormatException('Invalid transport optimization result');
    }
  }
}
