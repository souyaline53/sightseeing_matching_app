import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'discovery_state.dart';

/// Keep each trip's browsing session alive when its route is closed.
final additionalDiscoveryCacheProvider = Provider<AdditionalDiscoveryCache>((
  ref,
) {
  final cache = AdditionalDiscoveryCache();
  ref.onDispose(cache.dispose);
  return cache;
});

class AdditionalDiscoveryCache {
  final _sessions = <String, ProviderContainer>{};

  ProviderContainer session(String tripId, ProviderContainer parent) =>
      _sessions.putIfAbsent(tripId, () {
        final previous = parent.read(discoveryProvider);
        final initial = previous.deck.isNotEmpty && !previous.aiLoading
            ? previous.copyWith(step: 3)
            : DiscoveryState(step: 3, interests: previous.interests);
        return ProviderContainer(
          parent: parent,
          overrides: [
            discoveryProvider.overrideWith(() => AdditionalDiscovery(initial)),
          ],
        );
      });

  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}

class AdditionalDiscovery extends DiscoveryNotifier {
  final DiscoveryState initial;
  bool _started = false;
  AdditionalDiscovery(this.initial);

  @override
  DiscoveryState build() => initial;

  Future<void> ensureLoaded(Map<String, dynamic> travelContext) async {
    if (_started || state.deck.isNotEmpty) return;
    _started = true;
    await showExplore(travelContext: travelContext);
  }
}
