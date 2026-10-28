import 'package:latlong2/latlong.dart';

class DeparturePlace {
  final String id, name, reading;
  final LatLng point;
  final bool bus;
  const DeparturePlace(
    this.id,
    this.name,
    this.reading,
    this.point, {
    this.bus = false,
  });
}

/// Prototype candidates with approximate coordinates, not a live station feed.
const departurePlaces = [
  DeparturePlace('sapporo', '札幌駅', 'さっぽろ sapporo', LatLng(43.0687, 141.3508)),
  DeparturePlace('otaru', '小樽駅', 'おたる otaru', LatLng(43.1972, 140.9937)),
  DeparturePlace('chitose', '新千歳空港', 'しんちとせ chitose', LatLng(42.787, 141.681)),
  DeparturePlace(
    'asahikawa',
    '旭川駅',
    'あさひかわ asahikawa',
    LatLng(43.7635, 142.358),
  ),
  DeparturePlace('hakodate', '函館駅', 'はこだて hakodate', LatLng(41.7738, 140.7264)),
  DeparturePlace('yubari', '新夕張駅', 'しんゆうばり yubari', LatLng(42.9369, 142.0345)),
  DeparturePlace(
    'odori-bus',
    '大通（バス停・サンプル）',
    'おおどおり odori bus',
    LatLng(43.06, 141.356),
    bus: true,
  ),
];
DeparturePlace? departureNamed(String name) {
  for (final place in departurePlaces) {
    if (place.name == name) return place;
  }
  return null;
}
