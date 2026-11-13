import 'dart:collection';
import 'transport.dart';

/// Keeps all Code ④ fields, including future/unknown fields, as immutable JSON.
Object? _freeze(Object? value) {
  if (value is Map) {
    if (value.keys.any((k) => k is! String)) {
      throw const FormatException('旅程データのキーが不正です。');
    }
    return UnmodifiableMapView<String, dynamic>(
      value.map((k, v) => MapEntry(k as String, _freeze(v))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value == null ||
      value is String ||
      value is bool ||
      (value is num && value.isFinite)) {
    return value;
  }
  throw const FormatException('旅程データの値が不正です。');
}

Json _map(Object? value) {
  if (value is! Map) throw const FormatException('旅程データの形式が不正です。');
  return _freeze(value) as Json;
}

List<Object?> _list(Json data, String key) {
  final value = data[key];
  if (value == null) return const [];
  if (value is! List) throw FormatException('$keyの形式が不正です。');
  return List<Object?>.unmodifiable(value);
}

List<Json> _objects(Json data, String key) =>
    List<Json>.unmodifiable(_list(data, key).map(_map));

int? _integer(Json data, String key) {
  final value = data[key];
  if (value == null) return null;
  if (value is! int || value < 0) throw FormatException('$keyの形式が不正です。');
  return value;
}

class TransportItinerarySummary {
  final Json data;
  TransportItinerarySummary(Json json) : data = _map(json);
  int? get departureSeconds => _integer(data, 'departureSeconds');
  int? get arrivalSeconds => _integer(data, 'arrivalSeconds');
  int? get transferCount => _integer(data, 'transferCount');
  int? get walkingSeconds => _integer(data, 'walkingSeconds');
}

class TransportItineraryLeg {
  final Json data;
  TransportItineraryLeg(Json json) : data = _map(json);
  String? get kind => data['kind'] as String?;
  int? get departureSeconds => _integer(data, 'departureSeconds');
  int? get arrivalSeconds => _integer(data, 'arrivalSeconds');
  List<Object?> get steps => _list(data, 'steps');
}

/// Distinct from the legacy candidates/selectedCandidateId preparation contract.
/// No conversion into TripState and no inferred or fabricated times.
class OptimizedTransportItinerary {
  final Json data;
  final String status;
  final String? candidateId;
  final bool? requiresReview;
  final TransportItinerarySummary summary;
  final List<Json> visits;
  final List<TransportItineraryLeg> legs;
  final List<Object?> steps, reviewReasons;

  factory OptimizedTransportItinerary.fromJson(Object? value) {
    final json = _map(value);
    if (json['status'] is! String ||
        (json['status'] as String).trim().isEmpty ||
        (json['candidateId'] != null && json['candidateId'] is! String) ||
        (json['requiresReview'] != null && json['requiresReview'] is! bool)) {
      throw const FormatException('交通最適化結果の形式が不正です。');
    }
    return OptimizedTransportItinerary._(json);
  }
  OptimizedTransportItinerary._(this.data)
    : status = data['status'] as String,
      candidateId = data['candidateId'] as String?,
      requiresReview = data['requiresReview'] as bool?,
      summary = TransportItinerarySummary(
        data['summary'] == null ? {} : _map(data['summary']),
      ),
      visits = _objects(data, 'visits'),
      legs = List.unmodifiable(
        _objects(data, 'legs').map(TransportItineraryLeg.new),
      ),
      steps = _list(data, 'steps'),
      reviewReasons = _list(data, 'reviewReasons');

  List<String> get visitOrder => data['visitOrder'] is List
      ? (data['visitOrder'] as List).cast<String>()
      : visits
            .map((v) => v['spotId'] ?? v['placeId'] ?? v['id'])
            .whereType<String>()
            .toList(growable: false);
  Json toJson() => data;
}

class TransportItineraryResponse {
  final OptimizedTransportItinerary itinerary;
  final String message;
  final Json metadata;
  const TransportItineraryResponse({
    required this.itinerary,
    required this.message,
    this.metadata = const {},
  });
}
