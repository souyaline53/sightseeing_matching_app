import 'dart:math' as math;
import '../model/experience.dart';
import '../model/search_settings.dart';

/// Illustrative ranking costs only: not a route, fare or feasibility guarantee.
class MockAccessRanking {
  static const _minutes = {
    'melon': 120,
    'coal': 140,
    'lake': 150,
    'otaru': 60,
    'craft': 60,
    'b walk': 45,
    'bread': 15,
    'hill': 240,
    'river': 70,
    'rail': 110,
  };
  double score(Experience e, SearchFilters filters) {
    final home = [
      '札幌',
      '小樽',
      '夕張',
      '旭川',
      '千歳',
      '江別',
      '函館',
    ].where(filters.origin.contains).firstOrNull;
    final local =
        home != null &&
        (e.area.contains(home) || home == '旭川' && e.area == '美瑛');
    final base = local
        ? 15
        : (_minutes[e.id] ?? 120) + (home == null || home == '札幌' ? 0 : 90);
    final minutes = filters.transport == TravelMode.transit
        ? base.toDouble()
        : base * .65;
    final cost =
        (e.category == 'ものづくり' ? 4000 : 1500) +
        minutes * (filters.transport == TravelMode.transit ? 20 : 12);
    final walk = e.category == '自然' || e.category == '街歩き' ? 30 : 10;
    return math.max(0, minutes - filters.maxMinutes) * 10 +
        math.max(0, cost - filters.budget) / 100 +
        (filters.walking == Walking.light ? walk : 0) +
        (filters.length == TripLength.halfDay
            ? math.max(0, minutes * 2 + e.minutes - 240)
            : 0) +
        minutes / 1000;
  }
}
