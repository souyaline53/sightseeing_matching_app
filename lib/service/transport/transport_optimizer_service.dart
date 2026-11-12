import 'package:cloud_functions/cloud_functions.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/transport.dart';
import '../../model/transport_optimization.dart';
import '../cloud/cloud_services.dart';
import 'transport_admin_api.dart';

/// Explicit preparation only. No Dify key or HTTP client belongs in Flutter.
final transportOptimizerProvider = Provider<TransportOptimizerService>(
  (ref) => TransportOptimizerService((input) async {
    final cloud = await ref.read(cloudServicesProvider.future);
    await cloud.writer();
    final result = await transportFunctions()
        .httpsCallable(
          'prepareTransportOptimization',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 70)),
        )
        .call<dynamic>(input);
    return Map<String, dynamic>.from(result.data as Map);
  }),
);

class TransportOptimizerService {
  final Future<Json> Function(Json) prepare;
  const TransportOptimizerService(this.prepare);
  Future<PreparedTransportOptimization> build(
    TransportOptimizationInput input,
  ) async =>
      PreparedTransportOptimization.fromJson(await prepare(input.toJson()));
}
