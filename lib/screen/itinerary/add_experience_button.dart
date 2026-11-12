import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../service/ai_matching_service.dart';
import '../../state/discovery_state.dart';
import '../../state/additional_discovery_cache.dart';
import '../../state/trip_state.dart';
import '../recommendation/experience_deck.dart';

class AddExperienceButton extends HookConsumerWidget {
  final String? tripId;
  final bool compact;
  const AddExperienceButton({super.key, this.tripId, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opening = useState(false);
    Future<void> openCards() async {
      if (opening.value) return;
      opening.value = true;
      try {
        if (tripId != null) ref.read(tripProvider.notifier).openPlan(tripId!);
        final trip = ref.read(tripProvider);
        final travelDate = trip.travelDate;
        final session = ref
            .read(additionalDiscoveryCacheProvider)
            .session(
              trip.id,
              ProviderScope.containerOf(context, listen: false),
            );
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => UncontrolledProviderScope(
              container: session,
              child: _AdditionalExperiences(
                travelContext: {
                  ...aiTravelContext(
                    trip.conditions,
                    trip.saved.map((e) => e.id),
                  ),
                  if (travelDate != null)
                    'visitDate':
                        '${travelDate.year.toString().padLeft(4, "0")}-${travelDate.month.toString().padLeft(2, "0")}-${travelDate.day.toString().padLeft(2, "0")}',
                },
              ),
            ),
          ),
        );
      } finally {
        if (context.mounted) opening.value = false;
      }
    }

    return OutlinedButton.icon(
      style: compact
          ? OutlinedButton.styleFrom(
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              textStyle: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontSize: 11),
            )
          : null,
      onPressed: opening.value ? null : openCards,
      icon: const Icon(Icons.add),
      label: const Text('体験を追加する'),
    );
  }
}

class _AdditionalExperiences extends HookConsumerWidget {
  final Map<String, dynamic> travelContext;
  const _AdditionalExperiences({required this.travelContext});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(() {
      var active = true;
      Future.microtask(() {
        if (active && context.mounted) {
          (ref.read(discoveryProvider.notifier) as AdditionalDiscovery)
              .ensureLoaded(travelContext);
        }
      });
      return () => active = false;
    }, const []);
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
