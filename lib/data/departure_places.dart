import 'package:latlong2/latlong.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/catalog_record.dart';
import '../model/transport.dart';
import '../repository/firestore_catalog_repository.dart';
import '../service/cloud/cloud_services.dart';

class DeparturePlace {
  final String id, name, reading, address;
  final LatLng point;
  final bool bus;
  final List<AccessStop> accessStops;
  const DeparturePlace(
    this.id,
    this.name,
    this.reading,
    this.point, {
    this.address = '',
    this.bus = false,
    this.accessStops = const [],
  });
  factory DeparturePlace.fromRecord(CatalogRecord record) => DeparturePlace(
    record.id,
    record.id,
    '',
    LatLng(
      (record.data['latitude'] as num).toDouble(),
      (record.data['longitude'] as num).toDouble(),
    ),
    address: record.data['address'] as String? ?? '',
    accessStops: (record.data['accessStops'] as List? ?? [])
        .map((e) => AccessStop(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

final departurePlacesProvider = StreamProvider<List<DeparturePlace>>((
  ref,
) async* {
  final cloud = ref.watch(cloudServicesProvider.future);
  final repository = FirestoreCatalogRepository(() => cloud);
  yield* repository
      .watchRecords(CatalogKind.departure)
      .map((records) => records.map(DeparturePlace.fromRecord).toList());
});

DeparturePlace? departureNamed(String name, Iterable<DeparturePlace> places) =>
    places.where((place) => place.id == name || place.name == name).firstOrNull;

// 旭川駅は現在、出発地として未対応。
bool isDepartureSelectable(String name) => name != '旭川駅';
