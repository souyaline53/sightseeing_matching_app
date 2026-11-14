import 'admin_transport_fields.dart';

const spotWeekdays = {
  'mon': '月曜日',
  'tue': '火曜日',
  'wed': '水曜日',
  'thu': '木曜日',
  'fri': '金曜日',
  'sat': '土曜日',
  'sun': '日曜日',
};
const recommendedSeasonOptions = {
  'spring': '春',
  'summer': '夏',
  'autumn': '秋',
  'winter': '冬',
};
const experienceTagOptions = [
  '探検',
  '癒やし',
  '学び',
  '非日常',
  '食体験',
  '自然',
  '歴史',
  '写真撮影',
  'アクティビティ',
  'ものづくり',
  '交流',
  '買い物',
  '絶景',
  '文化',
  '家族向け',
];
const openingStatusOptions = {
  'unknown': '営業時間不明',
  'scheduled': '曜日・時間で営業',
  'always_open': '営業時間の制限なし',
};
const seasonalStatusOptions = {
  'unknown': '営業期間不明',
  'year_round': '通年営業',
  'seasonal': '期間限定営業',
};
const environmentOptions = {
  'unknown': '不明',
  'indoor': '屋内',
  'outdoor': '屋外',
  'mixed': '屋内・屋外',
};
const feeStatusOptions = {
  'unknown': '料金不明',
  'free': '無料',
  'paid': '有料',
  'variable': '変動料金',
};

/// Visit metadata only: does not change recommendation candidates or infer open/free.
class SpotVisitInfo {
  final Map<String, dynamic> data;
  SpotVisitInfo.fromMap(Map<String, dynamic> source)
    : data = {
        'openingHoursStatus': 'unknown',
        'openingHours': null,
        'specialHours': <dynamic>[],
        'seasonalAvailability': {'status': 'unknown', 'periods': <dynamic>[]},
        'recommendedSeasons': <String>[],
        'environmentType': 'unknown',
        'admissionFee': {
          'status': 'unknown',
          'adultYen': null,
          'childYen': null,
          'note': '',
        },
        'reservationRequired': null,
        'experienceTags': <String>[],
        'officialUrl': '',
      } {
    for (final key in data.keys.toList()) {
      if (!source.containsKey(key)) continue;
      final value = source[key];
      if (data[key] is Map && value is Map) {
        data[key] = {...data[key] as Map, ...value};
      } else {
        data[key] = value;
      }
    }
    // Editable drafts must never mutate the original Firestore snapshot.
    final copy = _copyMap(data);
    data.clear();
    data.addAll(copy);
  }
  Map<String, dynamic> toMap() => _copyMap(data);

  void validate() {
    Never fail(String message) => throw FormatException(message);
    void choice(dynamic value, Map<String, String> options, String label) {
      if (value is! String || !options.containsKey(value)) {
        fail('$labelを選択してください。');
      }
    }

    choice(data['openingHoursStatus'], openingStatusOptions, '営業時間の登録状態');
    final opening = data['openingHours'];
    if (opening != null && opening is! Map) fail('曜日別営業時間の形式が不正です。');
    if (data['openingHoursStatus'] == 'scheduled' && opening is! Map) {
      fail('曜日別営業時間を設定してください。');
    }
    if (opening is Map) {
      for (final day in spotWeekdays.keys) {
        validateSpotHours(opening[day], label: spotWeekdays[day]!);
      }
    }
    final specials = data['specialHours'];
    if (specials is! List) fail('特別営業日の形式が不正です。');
    final dates = <String>{};
    for (final special in specials) {
      if (special is! Map ||
          special['date'] is! String ||
          !validAdminDate(special['date'])) {
        fail('特別営業日をYYYY-MM-DDで指定してください。');
      }
      if (!dates.add(special['date'])) fail('同じ特別営業日が重複しています。');
      if (special['closed'] is! bool || special['note'] is! String) {
        fail('特別営業日の休業設定・補足を確認してください。');
      }
      validateSpotHours(special['hours'], label: special['date']);
      if (special['closed']
          ? (special['hours'] as List).isNotEmpty
          : (special['hours'] as List).isEmpty) {
        fail('特別営業日は、休業なら時間帯を空に、営業なら時間帯を登録してください。');
      }
    }
    final seasonal = data['seasonalAvailability'];
    if (seasonal is! Map) fail('営業期間の形式が不正です。');
    choice(seasonal['status'], seasonalStatusOptions, '営業期間');
    final periods = seasonal['periods'];
    if (periods is! List ||
        (seasonal['status'] == 'seasonal' && periods.isEmpty)) {
      fail('営業期間を登録してください。');
    }
    for (final period in periods) {
      if (period is! Map) fail('営業期間の形式が不正です。');
      for (final prefix in ['start', 'end']) {
        final month = period['${prefix}Month'], day = period['${prefix}Day'];
        if (month is! int ||
            day is! int ||
            month < 1 ||
            month > 12 ||
            day < 1 ||
            DateTime.utc(2000, month, day).month != month) {
          fail('営業期間は実在する月日を指定してください。');
        }
      }
    }
    choice(data['environmentType'], environmentOptions, '屋内・屋外');
    final fee = data['admissionFee'];
    if (fee is! Map) fail('料金の形式が不正です。');
    choice(fee['status'], feeStatusOptions, '料金');
    for (final key in ['adultYen', 'childYen']) {
      final amount = fee[key];
      if (amount != null && (amount is! int || amount < 0)) {
        fail('料金は0以上の整数で指定してください。');
      }
    }
    if (fee['note'] is! String) fail('料金補足は文字列で指定してください。');
    if (data['reservationRequired'] != null &&
        data['reservationRequired'] is! bool) {
      fail('予約の必要性を選択してください。');
    }
    for (final key in ['recommendedSeasons', 'experienceTags']) {
      final values = data[key];
      if (values is! List ||
          values.any((v) => v is! String) ||
          values.toSet().length != values.length) {
        fail('$keyの形式が不正です。');
      }
      if (key == 'recommendedSeasons' &&
          values.any((v) => !recommendedSeasonOptions.containsKey(v))) {
        fail('おすすめの季節が不正です。');
      }
    }
    final url = data['officialUrl'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (url is! String ||
        (url.isNotEmpty &&
            (uri == null ||
                uri.scheme != 'https' ||
                uri.host.isEmpty ||
                uri.userInfo.isNotEmpty ||
                RegExp(r'\s').hasMatch(url)))) {
      fail('公式サイトはHTTPS URLで指定してください。');
    }
  }
}

void validateSpotHours(dynamic hours, {String label = '営業時間'}) {
  Never fail() => throw FormatException(
    '$label：時刻はHH:mm（00:00〜23:59、終了のみ24:00）で指定し、開始より後に終了してください。重複・日付をまたぐ営業は登録できません。',
  );
  if (hours is! List) fail();
  int parse(dynamic value, bool closing) {
    if (value is! String) fail();
    if (closing && value == '24:00') return 1440;
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) fail();
    return int.parse(value.substring(0, 2)) * 60 +
        int.parse(value.substring(3));
  }

  final ranges = <(int, int)>[];
  for (final row in hours) {
    if (row is! Map) fail();
    final start = parse(row['open'], false), end = parse(row['close'], true);
    if (start >= end) fail();
    ranges.add((start, end));
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  for (var i = 1; i < ranges.length; i++) {
    if (ranges[i].$1 < ranges[i - 1].$2) fail();
  }
}

/// Merge maps recursively while replacing lists, including intentional empty lists.
Map<String, dynamic> mergeCatalogMaps(
  Map<String, dynamic> current,
  Map<String, dynamic> changes,
) => {
  ...current,
  for (final entry in changes.entries)
    entry.key: current[entry.key] is Map && entry.value is Map
        ? mergeCatalogMaps(
            Map<String, dynamic>.from(current[entry.key] as Map),
            Map<String, dynamic>.from(entry.value as Map),
          )
        : entry.value,
};

/// Japan has no daylight saving. An instant is converted to Tokyo before evaluation.
/// Unknown is never reported as open. This function is not wired to the AI API.
enum SpotVisitStatus { open, closed, unknown }

SpotVisitStatus evaluateSpotVisit(
  SpotVisitInfo info,
  DateTime arrival, {
  int durationMinutes = 0,
}) {
  if (durationMinutes < 0) {
    throw ArgumentError.value(durationMinutes, 'durationMinutes');
  }
  info.validate();
  var japan = arrival.toUtc().add(const Duration(hours: 9));
  var remaining = durationMinutes.toDouble();
  var result = SpotVisitStatus.open;
  do {
    final midnight = DateTime.utc(japan.year, japan.month, japan.day + 1);
    final untilMidnight = midnight.difference(japan).inMicroseconds / 60000000;
    final part = remaining < untilMidnight ? remaining : untilMidnight;
    final status = _evaluateSpotVisitDay(info.data, japan, part);
    if (status == SpotVisitStatus.closed) return status;
    if (status == SpotVisitStatus.unknown) result = status;
    remaining -= part;
    japan = midnight;
  } while (remaining > 0);
  return result;
}

SpotVisitStatus _evaluateSpotVisitDay(
  Map<String, dynamic> data,
  DateTime japan,
  num durationMinutes,
) {
  final seasonal = data['seasonalAvailability'] as Map;
  if (seasonal['status'] == 'seasonal') {
    final date = japan.month * 100 + japan.day;
    final available = (seasonal['periods'] as List).any((p) {
      final start = p['startMonth'] * 100 + p['startDay'];
      final end = p['endMonth'] * 100 + p['endDay'];
      return start <= end
          ? date >= start && date <= end
          : date >= start || date <= end;
    });
    if (!available) return SpotVisitStatus.closed;
  }
  final date =
      '${japan.year.toString().padLeft(4, '0')}-${japan.month.toString().padLeft(2, '0')}-${japan.day.toString().padLeft(2, '0')}';
  List? hours;
  for (final special in data['specialHours'] as List) {
    if (special['date'] == date) {
      if (special['closed'] == true) return SpotVisitStatus.closed;
      hours = special['hours'] as List;
      break;
    }
  }
  if (hours == null) {
    if (data['openingHoursStatus'] == 'unknown') return SpotVisitStatus.unknown;
    if (data['openingHoursStatus'] == 'always_open') {
      return SpotVisitStatus.open;
    }
    hours =
        (data['openingHours'] as Map)[spotWeekdays.keys.elementAt(
              japan.weekday - 1,
            )]
            as List;
  }
  final minute =
      japan.hour * 60 +
      japan.minute +
      japan.second / 60 +
      japan.millisecond / 60000 +
      japan.microsecond / 60000000;
  int minutes(String value) =>
      int.parse(value.substring(0, 2)) * 60 + int.parse(value.substring(3));
  final ranges = [
    for (final range in hours)
      (minutes(range['open']), minutes(range['close'])),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final continuous = <(int, int)>[];
  for (final range in ranges) {
    if (continuous.isNotEmpty && continuous.last.$2 == range.$1) {
      continuous[continuous.length - 1] = (continuous.last.$1, range.$2);
    } else {
      continuous.add(range);
    }
  }
  for (final range in continuous) {
    if (minute >= range.$1 &&
        minute < range.$2 &&
        minute + durationMinutes <= range.$2) {
      return SpotVisitStatus.open;
    }
  }
  return SpotVisitStatus.closed;
}

Map<String, dynamic> _copyMap(Map<String, dynamic> value) => {
  for (final entry in value.entries) entry.key: _copyValue(entry.value),
};
dynamic _copyValue(dynamic value) {
  if (value is Map) return _copyMap(Map<String, dynamic>.from(value));
  if (value is List) return value.map(_copyValue).toList();
  return value;
}

/// Hours for the selected local calendar date; absent information stays blank.
String? spotOpeningHoursLabel(Map<String, dynamic> source, DateTime date) {
  final data = SpotVisitInfo.fromMap(source).data;
  final seasonal = data['seasonalAvailability'] as Map;
  if (seasonal['status'] == 'seasonal') {
    final md = date.month * 100 + date.day;
    final available = (seasonal['periods'] as List).any((period) {
      final start = period['startMonth'] * 100 + period['startDay'];
      final end = period['endMonth'] * 100 + period['endDay'];
      return start <= end ? md >= start && md <= end : md >= start || md <= end;
    });
    if (!available) return '休業日（営業期間外）';
  }
  final key =
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  final special = (data['specialHours'] as List)
      .where((entry) => entry['date'] == key)
      .firstOrNull;
  List? hours;
  if (special != null) {
    if (special['closed'] == true) return '休業日';
    hours = special['hours'] as List?;
  } else if (data['openingHoursStatus'] == 'always_open') {
    return '営業時間：24時間';
  } else if (data['openingHoursStatus'] == 'scheduled') {
    hours =
        (data['openingHours'] as Map?)?[spotWeekdays.keys.elementAt(
              date.weekday - 1,
            )]
            as List?;
  }
  if (hours == null) return null;
  if (hours.isEmpty) return '休業日';
  return '営業時間：${hours.map((range) => "${range['open']}〜${range['close']}").join(' / ')}';
}
