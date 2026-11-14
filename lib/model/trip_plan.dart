import 'dart:convert';
import 'transport.dart';
import 'dart:math';
import 'experience.dart';
import 'search_settings.dart';

class TripState {
  final Map<String, dynamic> ai;
  String get aiStatus => ai['status'] as String? ?? 'unused';
  bool get aiQuotaBlocked =>
      ai['blockedUntil'] is int &&
      (ai['blockedUntil'] as int) > DateTime.now().millisecondsSinceEpoch;
  bool get aiLocked => ['processing', 'uncertain'].contains(aiStatus);
  String get aiBasis => jsonEncode({
    'stops': stops.map((e) => e.id).toList(),
    'date': travelDate?.toIso8601String(),
    'departure': departureMinutes,
    'origin': origin,
    'destination': arrivalPlace,
    'length': conditions.length.name,
    'mode': conditions.transport.name,
    'stay': {for (final e in stops) e.id: stayMinutes[e.id] ?? e.minutes},
    'config': ai['config'],
  });
  bool get aiProposalValid {
    if (ai['basis'] == aiBasis) return true;
    // Preserve proposals saved by the earlier round-trip-only model.
    try {
      final old = jsonDecode(ai['basis'] as String) as Map;
      final current = jsonDecode(aiBasis) as Map;
      if (!old.containsKey('destination') &&
          !old.containsKey('length') &&
          arrivalPlace == origin &&
          (conditions.length == TripLength.day ||
              conditions.length == TripLength.halfDay)) {
        current.remove('destination');
        current.remove('length');
        return jsonEncode(old) == jsonEncode(current);
      }
    } catch (_) {}
    return false;
  }

  final String id, title;
  final String? destination;
  String get arrivalPlace => destination ?? origin;
  String get destinationEndpointId => departureEndpointId(arrivalPlace);
  final DateTime updatedAt;
  final List<Experience> saved, stops;
  final SearchConditions conditions;
  final DateTime? travelDate;
  final int departureMinutes;
  final List<TransportSelection> transportSelections;
  final Map<String, int> stayMinutes;
  TripState({
    this.ai = const {},
    this.destination,
    String? id,
    this.title = '',
    DateTime? updatedAt,
    List<Experience> saved = const [],
    List<Experience> stops = const [],
    this.conditions = const SearchConditions(),
    this.travelDate,
    this.departureMinutes = 8 * 60,
    this.transportSelections = const [],
    this.stayMinutes = const {},
  }) : id =
           id ??
           'trip-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}',
       updatedAt = updatedAt ?? DateTime.now().toUtc(),
       saved = List.unmodifiable(saved),
       stops = List.unmodifiable(stops);
  String get displayTitle => title.trim().isNotEmpty
      ? title
      : stops.isEmpty
      ? '新しい旅'
      : '${stops.first.area}の小さな旅';
  String get origin => conditions.origin;
  static String departureEndpointId(String origin) =>
      'departure:${Uri.encodeComponent(origin.trim())}';
  String get originEndpointId => departureEndpointId(origin);
  DateTime get date =>
      travelDate ?? DateTime.now().add(const Duration(days: 1));
  bool get publicTransport => conditions.transport != TravelMode.car;
  bool contains(Experience e) => saved.any((x) => x.id == e.id);
  TripState copyWith({
    Map<String, dynamic>? ai,
    String? destination,
    String? title,
    List<Experience>? saved,
    List<Experience>? stops,
    SearchConditions? conditions,
    DateTime? travelDate,
    bool clearDate = false,
    int? departureMinutes,
    List<TransportSelection>? transportSelections,
    Map<String, int>? stayMinutes,
  }) => TripState(
    ai: ai ?? this.ai,
    destination: destination ?? this.destination,
    id: id,
    transportSelections: (transportSelections ?? this.transportSelections)
        .where((s) {
          final next = stops ?? this.stops;
          if (next.isNotEmpty &&
              s.from == departureEndpointId(conditions?.origin ?? origin) &&
              s.to == next.first.id) {
            return true;
          }
          if (next.isNotEmpty &&
              s.from == next.last.id &&
              s.to ==
                  departureEndpointId(
                    destination ??
                        this.destination ??
                        conditions?.origin ??
                        origin,
                  )) {
            return true;
          }
          return List.generate(
            next.isNotEmpty ? next.length - 1 : 0,
            (i) => next[i].id == s.from && next[i + 1].id == s.to,
          ).contains(true);
        })
        .map(
          (s) =>
              travelDate != null ||
                  clearDate ||
                  (departureMinutes != null &&
                      departureMinutes != this.departureMinutes)
              ? TransportSelection({
                  ...s.data,
                  'serviceDate': null,
                  'verificationStatus': 'needsReview',
                })
              : s,
        )
        .toList(),
    departureMinutes: departureMinutes ?? this.departureMinutes,
    stayMinutes: stayMinutes ?? this.stayMinutes,
    title: title ?? this.title,
    updatedAt: DateTime.now().toUtc(),
    saved: saved ?? this.saved,
    stops: stops ?? this.stops,
    conditions: conditions ?? this.conditions,
    travelDate: clearDate ? null : travelDate ?? this.travelDate,
  );
  Map<String, dynamic> toJson() => {
    'ai': ai,
    'destination': destination,
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'saved': saved.map((e) => e.toJson(includeVisitInfo: true)).toList(),
    'stops': stops.map((e) => e.toJson(includeVisitInfo: true)).toList(),
    'conditions': conditions.toJson(),
    'travelDate': travelDate?.toIso8601String(),
    'departureMinutes': departureMinutes,
    'transportSelections': transportSelections.map((s) => s.toJson()).toList(),
    'stayMinutes': stayMinutes,
  };
  factory TripState.fromJson(Map<String, dynamic> json) => TripState(
    ai: Map<String, dynamic>.from(json['ai'] as Map? ?? {}),
    destination: json['destination'] as String?,
    id: json['id'] as String,
    transportSelections: (json['transportSelections'] as List? ?? [])
        .map((s) => TransportSelection(Map<String, dynamic>.from(s as Map)))
        .toList(),
    stayMinutes: Map<String, int>.from(json['stayMinutes'] as Map? ?? {}),
    title: json['title'] as String? ?? '',
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    saved: (json['saved'] as List)
        .map((e) => Experience.fromJson(e as Map<String, dynamic>))
        .toList(),
    stops: (json['stops'] as List)
        .map((e) => Experience.fromJson(e as Map<String, dynamic>))
        .toList(),
    conditions: SearchConditions.fromJson(
      json['conditions'] as Map<String, dynamic>,
    ),
    travelDate: DateTime.tryParse(json['travelDate'] as String? ?? ''),
    departureMinutes:
        json['departureMinutes'] is int &&
            (json['departureMinutes'] as int) >= 0 &&
            (json['departureMinutes'] as int) < 1440
        ? json['departureMinutes'] as int
        : 480,
  );
}

/// The existing trip state is also the canonical saved plan.
typedef TripPlan = TripState;

class TripLibrary {
  final List<TripState> plans;
  final List<Experience> savedSpots;
  final String? activeId;
  TripLibrary({
    required List<TripState> plans,
    List<Experience>? savedSpots,
    String? activeId,
  }) : plans = List.unmodifiable(plans),
       savedSpots = List.unmodifiable(
         savedSpots ??
             {
               for (final plan in plans)
                 for (final spot in plan.saved) spot.id: spot,
             }.values,
       ),
       activeId = plans.any((p) => p.id == activeId)
           ? activeId
           : fallback(plans)?.id;
  factory TripLibrary.empty() => TripLibrary(plans: const []);
  TripState? get activeTrip => plans.where((p) => p.id == activeId).firstOrNull;

  static TripState? fallback(List<TripState> plans, [DateTime? now]) {
    final time = now ?? DateTime.now();
    final today = DateTime(time.year, time.month, time.day);
    final future =
        plans
            .where(
              (p) =>
                  p.travelDate != null &&
                  !DateTime(
                    p.travelDate!.year,
                    p.travelDate!.month,
                    p.travelDate!.day,
                  ).isBefore(today),
            )
            .toList()
          ..sort((a, b) {
            final date = a.travelDate!.compareTo(b.travelDate!);
            return date == 0 ? b.updatedAt.compareTo(a.updatedAt) : date;
          });
    if (future.isNotEmpty) return future.first;
    final undated = plans.where((p) => p.travelDate == null).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (undated.isNotEmpty) return undated.first;
    final others = [...plans]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return others.firstOrNull;
  }

  List<TripState> upcoming([DateTime? now]) {
    final time = now ?? DateTime.now();
    final today = DateTime(time.year, time.month, time.day);
    final eligible = plans
        .where(
          (p) =>
              (p.travelDate == null ||
              !DateTime(
                p.travelDate!.year,
                p.travelDate!.month,
                p.travelDate!.day,
              ).isBefore(today)),
        )
        .toList();
    eligible.sort((a, b) {
      if (a.travelDate != null && b.travelDate == null) return -1;
      if (a.travelDate == null && b.travelDate != null) return 1;
      if (a.travelDate != null && b.travelDate != null) {
        final order = a.travelDate!.compareTo(b.travelDate!);
        if (order != 0) return order;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return eligible;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'activeId': activeId,
    'savedSpots': savedSpots
        .map((e) => e.toJson(includeVisitInfo: true))
        .toList(),
    'plans': plans.map((p) => p.toJson()).toList(),
  };
  factory TripLibrary.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported trip data');
    }
    final plans = (json['plans'] as List)
        .map((p) => TripState.fromJson(p as Map<String, dynamic>))
        .toList();
    if (plans.map((p) => p.id).toSet().length != plans.length) {
      throw const FormatException('Duplicate trip ids');
    }
    return TripLibrary(
      plans: plans,
      activeId: json['activeId'] as String?,
      savedSpots: (json['savedSpots'] as List?)
          ?.map((e) => Experience.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
