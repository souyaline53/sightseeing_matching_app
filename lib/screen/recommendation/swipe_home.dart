import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/catalog_data.dart';
import '../../state/discovery_state.dart';
import '../../widgets/trip_from_saved_button.dart';
import 'experience_deck.dart';

/// A separate session keeps random discovery independent of the question flow.
class RandomDiscovery extends DiscoveryNotifier {
  @override
  DiscoveryState build() {
    final spots = [...ref.watch(catalogProvider).requireValue.experiences]
      ..shuffle();
    return DiscoveryState(step: 3, deck: spots.take(10).toList());
  }
}

class SwipeHome extends StatelessWidget {
  const SwipeHome({super.key});
  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [discoveryProvider.overrideWith(RandomDiscovery.new)],
    child: const _SwipePage(),
  );
}

class _SwipePage extends StatelessWidget {
  const _SwipePage();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('スワイプ')),
    body: const SafeArea(top: false, child: ExperienceDeck(random: true)),
    bottomNavigationBar: const TripFromSavedButton(),
  );
}
