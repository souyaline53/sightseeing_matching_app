import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/departure_places.dart';
import 'package:sightseeing_matching_app/model/catalog_record.dart';
import 'package:sightseeing_matching_app/repository/transport_repository.dart';

const values = {
  'address': '北海道札幌市北区北6条西4丁目1番1号',
  'latitude': 43.068455,
  'longitude': 141.349243,
  'accessStops': [
    {
      'stopId': 'gtfs~platform1',
      'stopName': '札幌駅前',
      'walkingMinutes': 7,
      'walkingDistanceMeters': 400,
      'sourceType': 'manual',
      'verificationStatus': 'unverified',
      'isActive': true,
    },
    {
      'stopId': 'gtfs~platform2',
      'stopName': '札幌駅北口',
      'walkingMinutes': 3,
      'isActive': false,
    },
  ],
};
void main() {
  test(
    'departure records share coordinates and access-stop structure; Japanese IDs are supported',
    () {
      expect(
        validateCatalogRecord(CatalogKind.departure, '札幌駅', values),
        isNull,
      );
      for (final id in ['', 'a/b', '..', ' 札幌駅', 'a\nb']) {
        expect(
          validateCatalogRecord(CatalogKind.departure, id, values),
          isNotNull,
        );
      }
      for (final invalid in [
        {...values, 'latitude': null},
        {...values, 'latitude': double.nan},
        {...values, 'longitude': 181},
        {
          ...values,
          'accessStops': [
            {'stopId': 'x', 'walkingMinutes': -1},
          ],
        },
      ]) {
        expect(
          validateCatalogRecord(CatalogKind.departure, '札幌駅', invalid),
          isNotNull,
        );
      }
      final record = CatalogRecord('札幌駅', CatalogKind.departure, values);
      final place = DeparturePlace.fromRecord(record);
      expect(record.displayName, '札幌駅');
      expect(record.photos, isEmpty);
      expect(place.address, values['address']);
      expect(place.accessStops.first.walkingMinutes, 7);
      expect(place.point.latitude, values['latitude']);
    },
  );
  test(
    'origin transport uses registered stops for any ID and retains walking data',
    () async {
      final place = DeparturePlace.fromRecord(
        CatalogRecord('新しい出発地', CatalogKind.departure, values),
      );
      final container = ProviderContainer(
        overrides: [
          departurePlacesProvider.overrideWith((ref) => Stream.value([place])),
        ],
      );
      addTearDown(container.dispose);
      container.listen(originTransportStopsProvider('新しい出発地'), (_, _) {});
      container.listen(originTransportStopsProvider('未登録'), (_, _) {});
      final stops = await container.read(
        originTransportStopsProvider('新しい出発地').future,
      );
      expect(stops.map((s) => s.id), ['gtfs~platform1']);
      expect(stops.single.data['walkingMinutes'], 7);
      expect(stops.single.data['walkingDistanceMeters'], 400);
      expect(
        await container.read(originTransportStopsProvider('未登録').future),
        isEmpty,
      );
    },
  );
}
