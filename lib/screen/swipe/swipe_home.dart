import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/swipe_state.dart';
import '../../state/discovery_state.dart';
import '../../widgets/trip_from_saved_button.dart';
import '../shared/experiences/widgets/experience_deck.dart';

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
