import '../data/catalog_data.dart';
import 'discovery_state.dart';

/// A separate session keeps random discovery independent of the question flow.
class RandomDiscovery extends DiscoveryNotifier {
  @override
  DiscoveryState build() {
    final spots = [...ref.watch(catalogProvider).requireValue.experiences]
      ..shuffle();
    return DiscoveryState(step: 3, deck: spots.take(10).toList());
  }
}
