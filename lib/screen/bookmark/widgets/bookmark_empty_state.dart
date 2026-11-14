import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../state/trip_library_state.dart';
import '../../../navigation/travel_navigation.dart';
import '../../../theme/app_theme.dart';
import 'booklet_illustration.dart';

class BookmarkEmptyState extends HookConsumerWidget {
  final VoidCallback onSearch;
  const BookmarkEmptyState({super.key, required this.onSearch});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSaved = ref.watch(savedExperiencesProvider).isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 720,
              minHeight: constraints.maxHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'あなたの次の旅行プラン',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppColors.surface, AppColors.softSurface],
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(
                          height: 230,
                          width: 310,
                          child: BookletIllustration(),
                        ),
                        const SizedBox(height: 22),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: const Text(
                            'まだ旅のしおりが\nありません',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              height: 1.6,
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 18),
                          height: 3,
                          width: 150,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        Text(
                          hasSaved
                              ? '保存したお気に入りを、ひとつの旅に。'
                              : '気になる場所を保存して、あなたの旅を作りましょう。',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.muted,
                            height: 1.8,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 26),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: hasSaved
                                ? () => openItinerarySetup(context, ref)
                                : onSearch,
                            icon: Icon(
                              hasSaved
                                  ? Icons.route_outlined
                                  : Icons.travel_explore,
                            ),
                            label: Text(
                              hasSaved ? '保存した観光地から旅を作る' : 'Step1. 興味から旅行を作る',
                              textAlign: TextAlign.center,
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
