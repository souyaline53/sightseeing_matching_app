import 'experience.dart';
import 'search_settings.dart';
import 'spot_visit_info.dart';
import 'transport.dart';

int tripNights(TripLength length) => switch (length) {
  TripLength.halfDay || TripLength.day => 0,
  TripLength.overnight => 1,
  TripLength.longer => 2,
};
DateTime tripArrivalDate(DateTime departure, TripLength length) => DateTime(
  departure.year,
  departure.month,
  departure.day + tripNights(length),
);

AccessStop? defaultBoardingStop(String placeName, List<AccessStop> stops) {
  final active = stops
      .where((s) => s.data['isActive'] != false && s.status != 'sample')
      .toList();
  if (placeName.contains('札幌')) {
    final jr = active
        .where(
          (s) =>
              s.stopId.startsWith('jr_hokkaido~') &&
              (s.data['stopName'] == '札幌' || s.data['stopName'] == '札幌駅'),
        )
        .firstOrNull;
    if (jr != null) return jr;
    final otherJr = active
        .where((s) => s.stopId.startsWith('jr_hokkaido~'))
        .firstOrNull;
    if (otherJr != null) return otherJr;
  }
  return active.where((s) => s.data['isPrimary'] == true).firstOrNull ??
      active.firstOrNull;
}

String boardingStopLabel(AccessStop stop) {
  final name =
      stop.data['stopName'] as String? ??
      stop.data['name'] as String? ??
      '名称未登録';
  final agency =
      stop.data['agencyName'] as String? ??
      (stop.stopId.startsWith('jr_hokkaido~') ? 'JR北海道' : '');
  return agency.isEmpty ? name : '$agency「$name」';
}

/// The endpoint is the selected boarding/alighting stop itself, so access is zero.
Json boardingAccess(AccessStop stop) => {
  ...stop.toJson(),
  'walkingMinutes': 0,
  'verificationStatus': 'verified',
};

/// Resolve registered weekly, exceptional and seasonal hours across all trip dates.
/// Missing hours never block a visit. Mixed unknown days are explicitly marked.
Json tripOpening(Experience spot, DateTime start, DateTime end) {
  final info = SpotVisitInfo.fromMap(spot.visitInfo);
  info.validate();
  final data = info.data;
  final windows = <List<int>>[];
  var unknown = false;
  final days = DateTime.utc(
    end.year,
    end.month,
    end.day,
  ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
  int seconds(String value) {
    final p = value.split(':');
    return (int.parse(p[0]) * 60 + int.parse(p[1])) * 60;
  }

  for (var offset = 0; offset <= days; offset++) {
    final day = DateTime.utc(start.year, start.month, start.day + offset);
    final seasonal = data['seasonalAvailability'] as Map;
    if (seasonal['status'] == 'seasonal') {
      final md = day.month * 100 + day.day;
      final inSeason = (seasonal['periods'] as List).any((p) {
        final a = p['startMonth'] * 100 + p['startDay'],
            b = p['endMonth'] * 100 + p['endDay'];
        return a <= b ? md >= a && md <= b : md >= a || md <= b;
      });
      if (!inSeason) {
        continue;
      }
    }
    final date =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final special = (data['specialHours'] as List)
        .where((s) => s['date'] == date)
        .firstOrNull;
    List? ranges;
    if (special != null) {
      if (special['closed'] == true) continue;
      ranges = special['hours'] as List;
    } else if (data['openingHoursStatus'] == 'always_open') {
      windows.add([offset * 86400, (offset + 1) * 86400]);
      continue;
    } else if (data['openingHoursStatus'] == 'scheduled') {
      ranges =
          (data['openingHours'] as Map)[spotWeekdays.keys.elementAt(
                day.weekday - 1,
              )]
              as List;
    } else {
      unknown = true;
      windows.add([offset * 86400, (offset + 1) * 86400]);
      continue;
    }
    for (final r in ranges) {
      windows.add([
        offset * 86400 + seconds(r['open'] as String),
        offset * 86400 + seconds(r['close'] as String),
      ]);
    }
  }
  // Adjacent open days form one interval, including visits spanning midnight.
  windows.sort((a, b) => a[0].compareTo(b[0]));
  final merged = <List<int>>[];
  for (final window in windows) {
    if (merged.isNotEmpty && window[0] <= merged.last[1]) {
      if (window[1] > merged.last[1]) merged.last[1] = window[1];
    } else {
      merged.add([...window]);
    }
  }
  return {
    'status': merged.isEmpty ? 'closed' : 'known',
    'windows': merged,
    if (unknown) 'assumedOpen': true,
  };
}
