import 'experience.dart';

class MockCatalog {
  final List<Experience> experiences;
  final List<TransitSample> transit;
  MockCatalog({
    required List<Experience> experiences,
    required List<TransitSample> transit,
  }) : experiences = List.unmodifiable(experiences),
       transit = List.unmodifiable(transit);

  List<TransitLeg> sampleTransit(String origin, List<Experience> stops) => [
    for (var i = 0; i < stops.length; i++) _leg(origin, stops, i),
  ];

  TransitLeg _leg(String origin, List<Experience> stops, int index) {
    final matches = transit
        .where(
          (sample) =>
              (sample.position == 'any' ||
                  sample.position == (index == 0 ? 'first' : 'following')) &&
              (sample.spotId == '*' || sample.spotId == stops[index].id),
        )
        .toList();
    final specific = matches
        .where((sample) => sample.spotId == stops[index].id)
        .firstOrNull;
    final sample = specific ?? matches.firstOrNull;
    final from = index == 0 ? origin : stops[index - 1].area;
    if (sample == null) {
      return TransitLeg(
        mode: '交通サンプル未登録',
        from: from,
        to: stops[index].area,
        departure: '未確認',
        arrival: '未確認',
        transfer: '未確認',
        walking: '未確認',
        fare: '未確認',
      );
    }
    return TransitLeg(
      mode: sample.mode,
      from: from,
      to: stops[index].area,
      departure: _time(sample.departureMinutes + index * sample.stepMinutes),
      arrival: _time(sample.arrivalMinutes + index * sample.stepMinutes),
      transfer: sample.transfer,
      walking: sample.walking,
      fare: sample.fare,
      photo: sample.photo,
      note: sample.note,
    );
  }

  String _time(int minutes) {
    final day = minutes ~/ 1440;
    final hour = (minutes % 1440) ~/ 60;
    final minute = minutes % 60;
    return '${day > 0 ? '+$day日 ' : ''}${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}

class TransitSample {
  final String id, position, spotId, mode, transfer, walking, fare, photo, note;
  final int departureMinutes, arrivalMinutes, stepMinutes;
  const TransitSample({
    required this.id,
    required this.position,
    required this.spotId,
    required this.mode,
    required this.transfer,
    required this.walking,
    required this.fare,
    required this.departureMinutes,
    required this.arrivalMinutes,
    required this.stepMinutes,
    this.photo = '',
    this.note = '',
  });
}
