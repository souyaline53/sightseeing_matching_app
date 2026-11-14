import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../state/trip_library_state.dart';
import '../../../navigation/travel_navigation.dart';
import 'bookmark_experience_gallery.dart';

class BookmarkEmptyState extends HookConsumerWidget {
  final VoidCallback onSearch;
  const BookmarkEmptyState({super.key, required this.onSearch});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, upperConstraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: upperConstraints.maxHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary.withValues(alpha: .07),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                Icons.landscape_outlined,
                                size: 64,
                                color: colors.primary,
                              ),
                              Positioned(
                                right: 8,
                                top: 12,
                                child: Icon(
                                  Icons.auto_awesome,
                                  size: 20,
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'まだ旅のしおりがありません',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '気になる観光地から旅を作りましょう。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            height: 1.7,
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: ref.watch(savedExperiencesProvider).isEmpty
                              ? FilledButton.icon(
                                  onPressed: onSearch,
                                  icon: const Icon(Icons.travel_explore),
                                  label: const Text('Step1. 興味から旅行を作る'),
                                )
                              : FilledButton.icon(
                                  onPressed: () =>
                                      openItinerarySetup(context, ref),
                                  icon: const Icon(Icons.route_outlined),
                                  label: const Text('Step2. 交通を選んで旅程を完成'),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
            child: BookmarkExperienceGallery(
              photoHeight: (constraints.maxHeight * .3 - 54).clamp(80.0, 150.0),
            ),
          ),
        ],
      ),
    );
  }
}
