import 'dart:math' as math;
import 'transport.dart';

String transportDirection(String destination) =>
    RegExp(r'(方面|行き|行)$').hasMatch(destination)
    ? destination
    : '$destination方面';
String stopSelectionLabel(Json stop) {
  final name =
      (stop['name'] ?? stop['stopName'] ?? stop['id'] ?? stop['stopId'])
          .toString();
  final destinations = (stop['stopDestinations'] as List? ?? []).cast<String>();
  final platform = stop['platformCode'] as String?;
  final detail = destinations.map(transportDirection).join('・');
  return '$name${detail.isEmpty ? '' : '／$detail'}${platform == null || platform.isEmpty ? '' : '（乗り場 $platform）'}';
}

const sameNameStopRadiusMeters = 500;

List<List<Json>> groupStopSelections(List<Json> stops) {
  final groups = <List<Json>>[];
  final seen = <String>{};
  final sorted = [...stops]
    ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  for (final stop in sorted.where((s) => s['isActive'] != false)) {
    if (!seen.add(stop['id'] as String)) continue;
    final name = (stop['name'] as String? ?? '').trim();
    final group = groups
        .where(
          (g) =>
              name.isNotEmpty &&
              (g.first['name'] as String? ?? '').trim() == name &&
              g.every(
                (other) =>
                    (stopDistanceMeters(stop, other) ?? double.infinity) <=
                    sameNameStopRadiusMeters,
              ),
        )
        .firstOrNull;
    if (group == null) {
      groups.add([stop]);
    } else {
      group.add(stop);
    }
  }
  // Visual groups have diameter <=500m. Routing uses direct pairs so boundary peers remain searchable.
  return groups..sort(
    (a, b) => (a.first['name'] as String? ?? '').compareTo(
      b.first['name'] as String? ?? '',
    ),
  );
}

List<Json> appendAccessStopSelections(
  List<Json> existing,
  List<Json> selected, {
  int maxRows = 30,
}) {
  final ids = existing.map((s) => s['stopId']).toSet();
  final additions = <Json>[];
  for (final stop in selected) {
    final id = stop['id'] as String;
    if (!ids.add(id)) continue;
    additions.add({
      'stopId': id,
      'stopName': stop['name'],
      'stopDestinations': List<String>.from(
        stop['stopDestinations'] as List? ?? [],
      ),
      if (stop['platformCode'] != null) 'platformCode': stop['platformCode'],
      'walkingMinutes': null,
      'walkingDistanceMeters': null,
      'isPrimary': false,
      'isActive': true,
      'sourceType': 'manual',
      'verificationStatus': 'unverified',
    });
  }
  if (existing.length + additions.length > maxRows) {
    throw FormatException('最寄り停留所は$maxRows件まで登録できます。選択数を減らしてください');
  }
  return [...existing, ...additions];
}

double? stopDistanceMeters(Json a, Json b) {
  if (a['latitude'] is! num ||
      a['longitude'] is! num ||
      b['latitude'] is! num ||
      b['longitude'] is! num) {
    return null;
  }
  final latA = (a['latitude'] as num).toDouble(),
      latB = (b['latitude'] as num).toDouble();
  final lonA = (a['longitude'] as num).toDouble(),
      lonB = (b['longitude'] as num).toDouble();
  if (![latA, latB, lonA, lonB].every((v) => v.isFinite) ||
      latA.abs() > 90 ||
      latB.abs() > 90 ||
      lonA.abs() > 180 ||
      lonB.abs() > 180) {
    return null;
  }
  final x = latA * math.pi / 180, y = latB * math.pi / 180;
  final d = y - x, l = (lonB - lonA) * math.pi / 180;
  final h =
      math.pow(math.sin(d / 2), 2) +
      math.cos(x) * math.cos(y) * math.pow(math.sin(l / 2), 2);
  return 6371000 * 2 * math.asin(math.sqrt(h.clamp(0, 1)));
}

int? stopGroupDistanceMeters(List<Json> stops) {
  double? maximum;
  for (var i = 0; i < stops.length; i++) {
    for (var j = i + 1; j < stops.length; j++) {
      final distance = stopDistanceMeters(stops[i], stops[j]);
      if (distance != null) {
        maximum = maximum == null ? distance : math.max(maximum, distance);
      }
    }
  }
  return maximum?.round();
}
