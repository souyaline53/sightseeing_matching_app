import '../../data/catalog_data.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/material.dart';
import '../../model/experience.dart';
import '../../state/trip_state.dart';
import '../../widgets/travel_photo.dart';
import '../posts/spot_reviews.dart';

void showExperience(BuildContext context, Experience experience) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (context) => FractionallySizedBox(
      heightFactor: .94,
      child: ExperienceDetail(experience: experience),
    ),
  );
}

class ExperienceDetail extends HookConsumerWidget {
  final Experience experience;
  const ExperienceDetail({super.key, required this.experience});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final experience =
        ref
            .watch(catalogProvider)
            .value
            ?.experiences
            .where((item) => item.id == this.experience.id)
            .firstOrNull ??
        this.experience;
    final trip = ref.watch(tripProvider);
    return Material(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 320, child: TravelPhoto(experience)),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${experience.area}  /  ${experience.category}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        experience.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        experience.story,
                        style: const TextStyle(height: 1.9),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'もう一歩、奥へ。',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        experience.surprise,
                        style: const TextStyle(height: 1.8),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          height: 140,
                          child: TravelPhoto(experiencesCompanion(experience)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('所要時間の目安：約${experience.minutes}分'),
                      const SizedBox(height: 8),
                      const Text(
                        '写真はイメージです。体験内容・営業状況は未確認のサンプルです。',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => ref
                              .read(tripProvider.notifier)
                              .toggle(experience),
                          icon: Icon(
                            trip.contains(experience)
                                ? Icons.favorite
                                : Icons.favorite_border,
                          ),
                          label: Text(
                            trip.contains(experience) ? '保存済み・解除する' : 'この体験を保存',
                          ),
                        ),
                      ),
                      SpotReviews(spotId: experience.id),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: IconButton.filledTonal(
              tooltip: '閉じる',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }
}

Experience experiencesCompanion(Experience e) => Experience(
  '${e.id}-detail',
  e.title,
  e.area,
  e.category,
  e.description,
  e.story,
  e.surprise,
  e.additionalPhotos.firstOrNull ?? e.photo,
  e.minutes,
);
