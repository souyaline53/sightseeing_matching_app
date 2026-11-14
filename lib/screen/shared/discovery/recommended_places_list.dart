import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../state/discovery_state.dart';
import '../../../state/trip_library_state.dart';
import '../../../widgets/travel_photo.dart';
import '../experiences/experience_detail.dart';

class RecommendedPlacesList extends ConsumerWidget {
  const RecommendedPlacesList({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryProvider);
    if (discovery.aiLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (discovery.aiError != null || discovery.deck.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(discovery.aiError ?? 'おすすめの観光地が見つかりませんでした。'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref
                    .read(discoveryProvider.notifier)
                    .showExplore(retry: true),
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
      );
    }
    final savedIds = ref
        .watch(savedExperiencesProvider)
        .map((e) => e.id)
        .toSet();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: discovery.deck.length,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final spot = discovery.deck[index];
        final saved = savedIds.contains(spot.id);
        return Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: InkWell(
            key: ValueKey('recommended-place-${spot.id}'),
            onTap: () => showExperience(context, spot),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 96,
                      height: 82,
                      child: TravelPhoto(spot),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spot.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          spot.area,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey('recommendation-save-${spot.id}'),
                    tooltip: saved ? '保存を取り消す' : '観光地を保存',
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () => ref
                        .read(tripLibraryProvider.notifier)
                        .toggleExperience(spot),
                    icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
