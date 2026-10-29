import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/mock_data.dart';
import '../../service/curiosity_questions.dart';
import '../../service/mock_access_ranking.dart';
import '../../service/recommendation_service.dart';
import '../../state/discovery_state.dart';
import '../../state/trip_state.dart';
import '../recommendation/experience_deck.dart';

class AddExperienceButton extends HookConsumerWidget {
  final String? tripId;
  const AddExperienceButton({super.key, this.tripId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opening = useState(false);
    Future<void> openCards() async {
      if (opening.value) return;
      opening.value = true;
      try {
        if (tripId != null) ref.read(tripProvider.notifier).openPlan(tripId!);
        final trip = ref.read(tripProvider);
        final interests = ref.read(discoveryProvider).interests;
        final ranking = MockAccessRanking();
        final deck = CuriosityQuestions.valid(interests)
            ? RecommendationService().recommendFor(
                interests,
                filters: trip.conditions,
              )
            : ([...experiences]..sort(
                (a, b) => ranking
                    .score(a, trip.conditions)
                    .compareTo(ranking.score(b, trip.conditions)),
              ));
        final initial = DiscoveryState(
          step: 3,
          interests: interests,
          deck: deck,
        );
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProviderScope(
              // Browsing here keeps the original search flow and answers intact.
              // Trip state and decoded photos remain shared with the parent scope.
              overrides: [
                discoveryProvider.overrideWith(
                  () => _AdditionalDiscovery(initial),
                ),
              ],
              child: const _AdditionalExperiences(),
            ),
          ),
        );
      } finally {
        if (context.mounted) opening.value = false;
      }
    }

    return OutlinedButton.icon(
      onPressed: opening.value ? null : openCards,
      icon: const Icon(Icons.add),
      label: const Text('体験を追加する'),
    );
  }
}

class _AdditionalDiscovery extends DiscoveryNotifier {
  final DiscoveryState initial;
  _AdditionalDiscovery(this.initial);
  @override
  DiscoveryState build() => initial;
}

class _AdditionalExperiences extends HookConsumerWidget {
  const _AdditionalExperiences();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(tripProvider.select((trip) => trip.stops.length));
    return Scaffold(
      appBar: AppBar(title: const Text('体験を追加する')),
      body: const SafeArea(top: false, child: ExperienceDeck()),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('旅程に戻る（$count件）'),
          ),
        ),
      ),
    );
  }
}
