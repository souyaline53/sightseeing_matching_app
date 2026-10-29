import 'dart:math';
import 'experience.dart';
import 'search_settings.dart';

class TripState {
  final String id, title;
  final DateTime updatedAt;
  final List<Experience> saved, stops;
  final SearchConditions conditions;
  final DateTime? travelDate;
  TripState({
    String? id,
    this.title = '',
    DateTime? updatedAt,
    List<Experience> saved = const [],
    List<Experience> stops = const [],
    this.conditions = const SearchConditions(),
    this.travelDate,
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
  DateTime get date =>
      travelDate ?? DateTime.now().add(const Duration(days: 1));
  bool get publicTransport => conditions.transport != TravelMode.car;
  bool contains(Experience e) => saved.any((x) => x.id == e.id);
  TripState copyWith({
    String? title,
    List<Experience>? saved,
    List<Experience>? stops,
    SearchConditions? conditions,
    DateTime? travelDate,
    bool clearDate = false,
  }) => TripState(
    id: id,
    title: title ?? this.title,
    updatedAt: DateTime.now().toUtc(),
    saved: saved ?? this.saved,
    stops: stops ?? this.stops,
    conditions: conditions ?? this.conditions,
    travelDate: clearDate ? null : travelDate ?? this.travelDate,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'saved': saved.map((e) => e.toJson()).toList(),
    'stops': stops.map((e) => e.toJson()).toList(),
    'conditions': conditions.toJson(),
    'travelDate': travelDate?.toIso8601String(),
  };
  factory TripState.fromJson(Map<String, dynamic> json) => TripState(
    id: json['id'] as String,
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
  );
}

/// The existing trip state is also the canonical saved plan.
typedef TripPlan = TripState;

class TripLibrary {
  final List<TripState> plans;
  final String? activeId;
  TripLibrary({required List<TripState> plans, String? activeId})
    : plans = List.unmodifiable(plans),
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
    return TripLibrary(plans: plans, activeId: json['activeId'] as String?);
  }
}
