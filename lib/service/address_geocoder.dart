import 'package:cloud_functions/cloud_functions.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'transport/transport_admin_api.dart';

final addressGeocoderProvider = Provider((ref) => AddressGeocoder());

class AddressGeocoder {
  Future<({double latitude, double longitude})> resolve(String address) async {
    try {
      final result = await transportFunctions()
          .httpsCallable('geocodeAddress')
          .call({'address': address});
      final data = result.data as Map;
      return (
        latitude: (data['latitude'] as num).toDouble(),
        longitude: (data['longitude'] as num).toDouble(),
      );
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? '住所を変換できません。緯度・経度を入力してください。');
    }
  }
}
