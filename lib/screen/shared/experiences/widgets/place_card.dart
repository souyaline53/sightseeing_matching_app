import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../../model/experience.dart';
import '../../../../state/trip_library_state.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/travel_photo.dart';
import '../experience_detail.dart';

/// The home preview shares the catalog card, with all actions omitted.
class PlaceCard extends ConsumerWidget {
  static const photoAspectRatio = 1.6;
  static double detailsHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    return (16 +
            scale.scale(14) * 1.3 +
            5 +
            (scale.scale(12) * 1.4).ceilToDouble() +
            7 +
            (scale.scale(11) * 1.4).ceilToDouble().clamp(15, double.infinity))
        .ceilToDouble();
  }

  final Experience experience;
  final bool interactive;
  const PlaceCard({
    super.key,
    required this.experience,
    this.interactive = true,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref
        .watch(savedExperiencesProvider)
        .any((e) => e.id == experience.id);
    final scale = MediaQuery.textScalerOf(context);
    return Material(
      color: AppColors.surface,
      elevation: 1.5,
      shadowColor: AppColors.ink.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('place-card-${experience.id}'),
        onTap: interactive ? () => showExperience(context, experience) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: photoAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TravelPhoto(experience),
                  if (experience.category.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      right: interactive ? 48 : 8,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: .94),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            experience.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (interactive)
                    Positioned(
                      top: 3,
                      right: 3,
                      child: IconButton.filledTonal(
                        key: ValueKey('place-save-${experience.id}'),
                        tooltip: saved ? '保存を取り消す' : '観光地を保存',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surface.withValues(
                            alpha: .95,
                          ),
                          foregroundColor: AppColors.primary,
                        ),
                        onPressed: () => ref
                            .read(tripLibraryProvider.notifier)
                            .toggleExperience(experience),
                        icon: Icon(
                          saved ? Icons.favorite : Icons.favorite_border,
                          size: 22,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: scale.scale(14) * 1.3,
                    child: Text(
                      experience.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    experience.description.isEmpty
                        ? experience.area
                        : experience.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 15,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          '約${experience.minutes}分',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
