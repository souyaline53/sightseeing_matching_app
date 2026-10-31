import 'dart:convert';

// Form definitions and validation are shared by the UI and save boundary.
enum AdminInput {
  text,
  id,
  integer,
  decimal,
  choice,
  date,
  time,
  toggle,
  rows,
  weekdays,
  url,
}

class AdminField {
  final String key, label;
  final AdminInput type;
  final bool required, multiline;
  final num? min, max;
  final Map<String, String> options;
  final List<AdminField> children;
  final String? reference;
  final int minRows, maxRows;
  const AdminField(
    this.key,
    this.label, {
    this.type = AdminInput.text,
    this.required = false,
    this.multiline = false,
    this.min,
    this.max,
    this.options = const {},
    this.children = const [],
    this.reference,
    this.minRows = 0,
    this.maxRows = 100,
  });
}

const statuses = {
  'sample': 'サンプル',
  'verified': '確認済み',
  'needsReview': '再確認が必要',
  'unverified': '未確認',
};
const sourceTypes = {
  'manual': '手動登録',
  'official': '公式情報',
  'gtfs': 'GTFS',
  'sample': 'サンプル',
};
const provenance = [
  AdminField(
    'sourceType',
    '情報の種類',
    type: AdminInput.choice,
    options: sourceTypes,
  ),
  AdminField('sourceUrl', '情報源のURL', type: AdminInput.url),
  AdminField('sourceCheckedAt', '情報の最終確認日', type: AdminInput.date),
  AdminField(
    'verificationStatus',
    '確認状態',
    type: AdminInput.choice,
    options: statuses,
  ),
];
const stopTimeFields = [
  AdminField(
    'stopId',
    '駅・バス停',
    type: AdminInput.id,
    required: true,
    reference: 'transport_stops',
  ),
  AdminField(
    'sequence',
    '停車順',
    type: AdminInput.integer,
    required: true,
    min: 1,
    max: 100000,
  ),
  AdminField('arrivalMinutes', '到着時刻', type: AdminInput.time),
  AdminField('departureMinutes', '出発時刻', type: AdminInput.time),
  AdminField('pickupAllowed', '乗車できる', type: AdminInput.toggle),
  AdminField('dropoffAllowed', '降車できる', type: AdminInput.toggle),
  AdminField('timeConfirmed', '時刻を確認済み', type: AdminInput.toggle),
];
const accessStopFields = [
  AdminField(
    'stopId',
    '最寄りの駅・バス停',
    type: AdminInput.id,
    required: true,
    reference: 'transport_stops',
  ),
  AdminField(
    'walkingMinutes',
    '入口までの徒歩時間（分・空欄は不明）',
    type: AdminInput.integer,
    min: 0,
    max: 100000,
  ),
  AdminField(
    'walkingDistanceMeters',
    '徒歩距離（m・空欄は不明）',
    type: AdminInput.integer,
    min: 0,
    max: 10000000,
  ),
  AdminField('isPrimary', '主なアクセスにする', type: AdminInput.toggle),
  ...provenance,
  AdminField('note', 'アクセスの補足', multiline: true),
];
const accessStopsField = AdminField(
  'accessStops',
  '最寄り駅・バス停',
  type: AdminInput.rows,
  children: accessStopFields,
  maxRows: 30,
);
List<AdminField> transportFields(String collection) => switch (collection) {
  'transport_agencies' => [
    const AdminField('name', '事業者名', required: true),
    const AdminField('website', '公式サイト', type: AdminInput.url),
    const AdminField(
      'timezone',
      'タイムゾーン',
      type: AdminInput.choice,
      required: true,
      options: {'Asia/Tokyo': '日本（Asia/Tokyo）'},
    ),
    const AdminField('gtfsAgencyId', 'GTFS事業者ID'),
    ...provenance,
  ],
  'transport_stops' => [
    const AdminField('name', '駅・バス停名', required: true),
    const AdminField(
      'type',
      '交通拠点の種類',
      required: true,
      type: AdminInput.choice,
      options: {'rail_station': '鉄道駅', 'bus_stop': 'バス停'},
    ),
    const AdminField(
      'latitude',
      '緯度（小数・空欄は不明）',
      type: AdminInput.decimal,
      min: -90,
      max: 90,
    ),
    const AdminField(
      'longitude',
      '経度（小数・空欄は不明）',
      type: AdminInput.decimal,
      min: -180,
      max: 180,
    ),
    const AdminField(
      'agencyId',
      '交通事業者',
      type: AdminInput.id,
      reference: 'transport_agencies',
    ),
    const AdminField(
      'parentStationId',
      '親となる駅',
      type: AdminInput.id,
      reference: 'transport_stops',
    ),
    const AdminField(
      'routeIds',
      '停車する路線',
      type: AdminInput.rows,
      children: [
        AdminField(
          'value',
          '路線',
          type: AdminInput.id,
          required: true,
          reference: 'transport_routes',
        ),
      ],
    ),
    const AdminField('gtfsStopId', 'GTFS停留所ID'),
    ...provenance,
  ],
  'transport_routes' => [
    const AdminField('name', '路線名', required: true),
    const AdminField(
      'agencyId',
      '交通事業者',
      required: true,
      type: AdminInput.id,
      reference: 'transport_agencies',
    ),
    const AdminField(
      'mode',
      '交通手段',
      required: true,
      type: AdminInput.choice,
      options: {
        'bus': 'バス',
        'rail': '鉄道',
        'tram': '路面電車',
        'subway': '地下鉄',
        'ferry': '船',
        'other': 'その他',
      },
    ),
    const AdminField('routeCode', '路線番号'),
    const AdminField('gtfsRouteId', 'GTFS路線ID'),
    ...provenance,
  ],
  'transport_services' => [
    const AdminField(
      'timezone',
      'タイムゾーン',
      type: AdminInput.choice,
      required: true,
      options: {'Asia/Tokyo': '日本（Asia/Tokyo）'},
    ),
    const AdminField(
      'validFrom',
      '運行期間の開始日',
      type: AdminInput.date,
      required: true,
    ),
    const AdminField(
      'validTo',
      '運行期間の終了日',
      type: AdminInput.date,
      required: true,
    ),
    const AdminField('weekdays', '運行する曜日', type: AdminInput.weekdays),
    const AdminField(
      'addedDates',
      '追加で運行する日',
      type: AdminInput.rows,
      children: [
        AdminField('value', '運行日', type: AdminInput.date, required: true),
      ],
    ),
    const AdminField(
      'removedDates',
      '運休する日',
      type: AdminInput.rows,
      children: [
        AdminField('value', '運休日', type: AdminInput.date, required: true),
      ],
    ),
    const AdminField('gtfsServiceId', 'GTFS運行日ID'),
    ...provenance,
  ],
  'transport_trips' => [
    const AdminField('name', '便の名前'),
    const AdminField(
      'routeId',
      '路線',
      type: AdminInput.id,
      required: true,
      reference: 'transport_routes',
    ),
    const AdminField(
      'serviceId',
      '運行日カレンダー',
      type: AdminInput.id,
      required: true,
      reference: 'transport_services',
    ),
    const AdminField('headsign', '行き先'),
    const AdminField('direction', '方向'),
    const AdminField(
      'stopTimes',
      '停車する駅・バス停と時刻',
      type: AdminInput.rows,
      children: stopTimeFields,
      minRows: 2,
      maxRows: 500,
    ),
    const AdminField('gtfsTripId', 'GTFS便ID'),
    ...provenance,
    const AdminField('note', '補足', multiline: true),
  ],
  'transport_fares' => [
    const AdminField(
      'routeId',
      '路線',
      type: AdminInput.id,
      required: true,
      reference: 'transport_routes',
    ),
    const AdminField(
      'fromStopId',
      '乗車する駅・バス停',
      type: AdminInput.id,
      required: true,
      reference: 'transport_stops',
    ),
    const AdminField(
      'toStopId',
      '降車する駅・バス停',
      type: AdminInput.id,
      required: true,
      reference: 'transport_stops',
    ),
    const AdminField(
      'amountYen',
      '運賃（円）',
      type: AdminInput.integer,
      required: true,
      min: 0,
      max: 10000000,
    ),
    const AdminField(
      'fareType',
      '運賃の種類',
      required: true,
      type: AdminInput.choice,
      options: {'adult': '大人', 'child': '小児', 'other': 'その他'},
    ),
    ...provenance,
    const AdminField('note', '補足', multiline: true),
  ],
  _ => throw ArgumentError('Unknown collection'),
};
bool validAdminDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final date = DateTime.tryParse(value);
  return date != null &&
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' ==
          value;
}

int? parseAdminTime(String text) {
  if (!RegExp(r'^\d{1,3}:[0-5]\d$').hasMatch(text)) return null;
  final parts = text.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

void validateAdminFields(List<AdminField> fields, Map<String, dynamic> data) {
  for (final f in fields) {
    final v = data[f.key];
    if (v == null || v == '') {
      if (f.required) throw FormatException('${f.label}を入力してください');
      continue;
    }
    bool ok = true;
    switch (f.type) {
      case AdminInput.text:
        ok = v is String && v.length <= 10000;
        break;
      case AdminInput.id:
        ok = v is String && RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(v);
        break;
      case AdminInput.url:
        final uri = v is String ? Uri.tryParse(v) : null;
        ok =
            uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty;
        break;
      case AdminInput.integer:
      case AdminInput.time:
        ok = v is int && v >= (f.min ?? 0) && v <= (f.max ?? 59999);
        break;
      case AdminInput.decimal:
        ok =
            v is num &&
            v.isFinite &&
            v >= (f.min ?? -double.maxFinite) &&
            v <= (f.max ?? double.maxFinite);
        break;
      case AdminInput.choice:
        ok = v is String && f.options.containsKey(v);
        break;
      case AdminInput.date:
        ok = v is String && validAdminDate(v);
        break;
      case AdminInput.toggle:
        ok = v is bool;
        break;
      case AdminInput.weekdays:
        ok =
            v is List &&
            v.every((e) => e is int && e >= 1 && e <= 7) &&
            v.toSet().length == v.length;
        break;
      case AdminInput.rows:
        ok = v is List && v.length >= f.minRows && v.length <= f.maxRows;
        if (ok) {
          for (final row in v) {
            if (f.children.length == 1 && f.children.first.key == 'value') {
              validateAdminFields(f.children, {'value': row});
            } else if (row is Map<String, dynamic>) {
              validateAdminFields(f.children, row);
            } else {
              ok = false;
              break;
            }
          }
        }
    }
    if (!ok) throw FormatException('${f.label}の形式・範囲を確認してください');
  }
}

void validateTransport(String collection, Map<String, dynamic> data) {
  validateAdminFields(transportFields(collection), data);
  if (collection == 'transport_stops' && data['routeIds'] is! List) {
    throw const FormatException('停車する路線の形式が不正です');
  }
  if (collection == 'transport_services') {
    if ((data['validFrom'] as String).compareTo(data['validTo'] as String) >
        0) {
      throw const FormatException('運行期間の終了日は開始日以降にしてください');
    }
    if (data['weekdays'] is! List ||
        data['addedDates'] is! List ||
        data['removedDates'] is! List) {
      throw const FormatException('運行日の形式が不正です');
    }
  }
  if (collection == 'transport_trips') {
    final times = data['stopTimes'];
    if (times is! List || times.length < 2) {
      throw const FormatException('停留所を2件以上登録してください');
    }
    final sorted =
        times.map((t) => Map<String, dynamic>.from(t as Map)).toList()..sort(
          (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int),
        );
    final sequences = <int>{};
    int last = -1;
    for (final t in sorted) {
      if (!sequences.add(t['sequence'] as int)) {
        throw const FormatException('停車順が重複しています');
      }
      for (final key in ['arrivalMinutes', 'departureMinutes']) {
        final v = t[key];
        if (v != null) {
          if ((v as int) < last) {
            throw const FormatException('発着時刻を停車順に並べてください（翌日は25:10等）');
          }
          last = v;
        }
      }
    }
  }
  // Existing unexposed metadata can contain Firestore Timestamp/GeoPoint.
  if (utf8.encode(jsonEncode(data, toEncodable: (v) => v.toString())).length >
      800000) {
    throw const FormatException('データが大きすぎます');
  }
}
