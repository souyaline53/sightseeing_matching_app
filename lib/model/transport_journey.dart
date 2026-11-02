import 'dart:convert';
import 'package:archive/archive.dart';
import 'transport.dart';

const maxTransportTransfers = 3;

String journeyTime(int seconds) {
  final day = seconds ~/ 86400;
  final minutes = (seconds % 86400) ~/ 60;
  final time = transportTime(minutes);
  final remainder = seconds % 60;
  return '${day == 0 ? '' : '$day日後 '}$time${remainder == 0 ? '' : ':${remainder.toString().padLeft(2, '0')}'}';
}

class TransportJourney {
  final Json data;
  TransportJourney(this.data);
  String get id => data['id'] as String;
  List<Json> get legs => (data['legs'] as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
  List<Json> get transfers => (data['transfers'] as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
  int get transferCount => data['transferCount'] as int;
  TransportSelection selection(
    String from,
    String to, {
    String? originName,
    bool fromOrigin = false,
    bool toOrigin = false,
  }) {
    final first = legs.first, last = legs.last;
    return TransportSelection({
      'fromSpotId': from,
      'toSpotId': to,
      'fromKind': fromOrigin ? 'origin' : 'spot',
      'toKind': toOrigin ? 'origin' : 'spot',
      'originName': ?originName,
      'journey': data,
      'serviceDate': data['queryDate'],
      'verificationStatus': data['verificationStatus'],
      'selectedTripId': first['tripId'],
      'boardingStopId': first['boardingStopId'],
      'boardingStopName': first['boardingStopName'],
      'alightingStopId': last['alightingStopId'],
      'alightingStopName': last['alightingStopName'],
      'departureSeconds': data['departureSeconds'],
      'arrivalSeconds': last['arrivalSeconds'],
      'departureMinutes': (data['departureSeconds'] as int) ~/ 60,
      'arrivalMinutes': (last['arrivalSeconds'] as int) ~/ 60,
      'walkingMinutesBefore': data['walkingMinutesBefore'],
      'walkingMinutesAfter': data['walkingMinutesAfter'],
    });
  }
}

class JourneySearchResult {
  final List<TransportJourney> journeys;
  final List<String> warnings;
  final bool walkingOnly;
  factory JourneySearchResult(Json data) {
    final pool = data['journeyPool'] as Map?;
    dynamic rows = data['journeys'];
    if (pool != null) {
      if (pool['encoding'] != 'gzip+base64' ||
          pool['rawBytes'] is! int ||
          (pool['rawBytes'] as int) > 2 * 1024 * 1024) {
        throw const FormatException('交通情報の形式を確認できません');
      }
      final bytes = GZipDecoder().decodeBytes(
        base64Decode(pool['data'] as String),
      );
      if (bytes.length != pool['rawBytes']) {
        throw const FormatException('交通情報の容量が一致しません');
      }
      rows = jsonDecode(utf8.decode(bytes));
    }
    return JourneySearchResult._(
      (rows as List)
          .map((r) => TransportJourney(Map<String, dynamic>.from(r as Map)))
          .toList(),
      (data['warnings'] as List? ?? []).cast<String>(),
      data['walkingOnly'] == true,
    );
  }
  JourneySearchResult._(this.journeys, this.warnings, this.walkingOnly);
}
