import '../home/home_screen.dart';
import '../../state/app_tab.dart';
import 'curiosity_question_flow.dart';
import '../search/search_conditions_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/discovery_state.dart';
import '../../state/trip_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'experience_deck.dart';

class RecommendationHome extends HookConsumerWidget {
  const RecommendationHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryProvider);
    final hasSavedCards = ref.watch(
      tripProvider.select((trip) => trip.saved.isNotEmpty),
    );
    final controller = ref.read(discoveryProvider.notifier);
    final step = discovery.step, question = discovery.question;
    final stage = switch (step) {
      2 => 1,
      1 => 2,
      _ => step,
    };
    final previousStage = useRef(stage);
    final direction = useRef(1.0);
    if (stage != previousStage.value) {
      direction.value = stage > previousStage.value ? 1 : -1;
      previousStage.value = stage;
    }
    if (step == 0) return const HomeScreen();
    final questionsOrExplore = Scaffold(
      appBar: AppBar(
        leading: step > 0
            ? IconButton(
                tooltip: '前の画面へ',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => controller.back(),
              )
            : const Icon(Icons.explore_outlined),
        title: const Text(
          'TABISAKI',
          style: TextStyle(
            letterSpacing: 4,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                step == 2 ? '${question + 1} / 3' : '体験を発見',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: step == 2
            ? const CuriosityQuestionFlow()
            : const ExperienceDeck(),
      ),
      bottomNavigationBar: step == 3
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: SizedBox(
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade600,
                    ),
                    onPressed: hasSavedCards
                        ? () => ref
                              .read(appTabProvider.notifier)
                              .select(AppTab.itinerary)
                        : null,
                    child: const Text('旅を組み立てる'),
                  ),
                ),
              ),
            )
          : null,
    );
    final page = step == 1
        ? const SearchConditionsScreen(key: ValueKey('conditions'))
        : KeyedSubtree(key: ValueKey(step), child: questionsOrExplore);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, animation) => SlideTransition(
          position:
              Tween<Offset>(
                begin: Offset(
                  child.key == page.key ? direction.value : -direction.value,
                  0,
                ),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOutCubic,
                ),
              ),
          child: child,
        ),
        child: page,
      ),
    );
  }
}
