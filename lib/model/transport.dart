typedef Json = Map<String, dynamic>;

String transportTime(int? minutes) => minutes == null
    ? '—'
    : '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
String verificationLabel(String status) => switch (status) {
  'sample' => 'サンプル時刻・実際の運行情報ではありません',
  'verified' => '確認済み（運行保証ではありません）',
  'needsReview' => '再確認が必要',
  _ => '交通情報未確認',
};

class AccessStop {
  final Json data;
  AccessStop(this.data);
  String get stopId => data['stopId'] as String;
  int? get walkingMinutes => data['walkingMinutes'] as int?;
  String get status => data['sourceType'] == 'sample'
      ? 'sample'
      : data['verificationStatus'] as String? ?? 'unverified';
  Json toJson() => {...data};
}

class TransportRecord {
  final String id;
  final Json data;
  TransportRecord(this.id, this.data);
  Json toJson() => {...data, 'id': id};
  String get name => data['name'] as String? ?? id;
}

class TransportAgency extends TransportRecord {
  TransportAgency(super.id, super.data);
}

class TransportStop extends TransportRecord {
  TransportStop(super.id, super.data);
}

class TransportRoute extends TransportRecord {
  TransportRoute(super.id, super.data);
}

class TransportFare extends TransportRecord {
  TransportFare(super.id, super.data);
}

class TransportService extends TransportRecord {
  TransportService(super.id, super.data);
  bool operates(DateTime date) {
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if ((data['removedDates'] as List? ?? []).contains(day)) return false;
    if ((data['addedDates'] as List? ?? []).contains(day)) return true;
    if (data['validFrom'] == null || data['validTo'] == null) return false;
    if (day.compareTo(data['validFrom'] as String) < 0 ||
        day.compareTo(data['validTo'] as String) > 0) {
      return false;
    }
    return (data['weekdays'] as List? ?? []).contains(date.weekday);
  }
}

class StopTime {
  final Json data;
  StopTime(this.data);
  String get stopId => data['stopId'] as String;
  int get sequence => data['sequence'] as int;
  int? get arrival => data['arrivalMinutes'] as int?;
  int? get departure => data['departureMinutes'] as int?;
  bool get pickup => data['pickupAllowed'] != false;
  bool get dropoff => data['dropoffAllowed'] != false;
}

class TransportTrip extends TransportRecord {
  TransportTrip(super.id, super.data);
  List<StopTime> get times =>
      (data['stopTimes'] as List)
          .map((e) => StopTime(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
  String get status => data['sourceType'] == 'sample'
      ? 'sample'
      : data['verificationStatus'] as String? ?? 'unverified';
}

class TransportSelection {
  final Json data;
  TransportSelection(this.data);
  Json toJson() => {...data};
  String get from => data['fromSpotId'] as String;
  String get to => data['toSpotId'] as String;
}
