import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/mock_data.dart';
import '../../widgets/travel_photo.dart';
import '../recommendation/experience_detail.dart';

/// Reuses the registered experiences and their existing detail sheet.
class HomeExperienceGallery extends HookConsumerWidget {
  final double photoHeight;
  const HomeExperienceGallery({super.key, this.photoHeight = 140});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'おすすめの体験',
          style: TextStyle(
            color: colors.primary,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: photoHeight,
          child: ListView.separated(
            key: const ValueKey('home-gallery-list'),
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: experiences.length,
            separatorBuilder: (_, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final experience = experiences[index];
              return SizedBox(
                width: photoHeight * .68,
                child: Semantics(
                  button: true,
                  label: '${experience.area}、${experience.title}。詳細を開く',
                  excludeSemantics: true,
                  onTap: () => showExperience(context, experience),
                  child: Material(
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('home-gallery-${experience.id}'),
                      onTap: () => showExperience(context, experience),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          TravelPhoto(experience),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.center,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black87],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 10,
                            child: Text(
                              experience.area,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'タップで詳細を見る · 写真・体験はイメージです',
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
