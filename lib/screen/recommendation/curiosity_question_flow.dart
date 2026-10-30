import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../service/curiosity_questions.dart';
import '../../state/discovery_state.dart';

class CuriosityQuestionFlow extends HookConsumerWidget {
  const CuriosityQuestionFlow({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryProvider);
    final controller = ref.read(discoveryProvider.notifier);
    final answers = discovery.interests;
    final number = discovery.question;
    void chooseMood(String id) {
      final current = ref.read(discoveryProvider);
      if (current.step != 2 || current.question != 0) return;
      Feedback.forTap(context);
      controller.selectMoodId(id);
    }

    void chooseOption(String id) {
      final current = ref.read(discoveryProvider);
      if (current.step != 2 || current.question != number) return;
      if (!controller.answerId(id)) return;
      Feedback.forTap(context);
      if (number == 2) controller.showConditions();
    }

    final previousNumber = useRef(number);
    final direction = useRef(1.0);
    if (previousNumber.value != number) {
      direction.value = number > previousNumber.value ? 1 : -1;
      previousNumber.value = number;
    }
    final quest = number == 2;
    final content = number == 0
        ? null
        : quest
        ? CuriosityQuestions.questsFor(answers.moodId, answers.reasonId)
        : CuriosityQuestions.reasonFor(answers.moodId);
    final options =
        content?.options ??
        [
          for (final mood in CuriosityQuestions.moods)
            QuestionOption(mood.id, mood.label, mood.symbol, mood.genres),
        ];
    final selectedId = number == 0
        ? answers.moodId
        : quest
        ? answers.questId
        : answers.reasonId;
    final page = SingleChildScrollView(
      key: ValueKey(
        'question-$number-${quest ? answers.reasonId : answers.moodId}',
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QuestionHeader(
            number: number + 1,
            title: content?.title ?? 'どんな気持ちになりたい？',
            hint: number == 0
                ? '直感でひとつ、心が動く気分を。'
                : quest
                ? 'ちょっと意外なクエストへ、踏み出してみませんか？'
                : 'どんなところに惹かれるか、教えてください。',
          ),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _AnswerCard(
                option: option,
                keyPrefix: number == 0
                    ? 'mood'
                    : quest
                    ? 'quest'
                    : 'reason',
                selected: selectedId == option.id,
                onTap: () => number == 0
                    ? chooseMood(option.id)
                    : chooseOption(option.id),
              ),
            ),
        ],
      ),
    );
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(
            begin: Offset(
              child.key == page.key ? direction.value : -direction.value,
              0,
            ),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
        child: page,
      ),
    );
  }
}

class _QuestionHeader extends HookConsumerWidget {
  final int number;
  final String title, hint;
  const _QuestionHeader({
    required this.number,
    required this.title,
    required this.hint,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LinearProgressIndicator(
        value: number / 3,
        minHeight: 4,
        borderRadius: BorderRadius.circular(4),
      ),
      const SizedBox(height: 18),
      Text(
        'Q$number  /  3',
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 8),
      Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            height: 1.4,
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        hint,
        style: TextStyle(
          fontSize: 13,
          height: 1.6,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 20),
    ],
  );
}

class _AnswerCard extends HookConsumerWidget {
  final QuestionOption option;
  final bool selected;
  final String keyPrefix;
  final VoidCallback onTap;
  const _AnswerCard({
    required this.option,
    required this.selected,
    required this.keyPrefix,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('$keyPrefix-${option.id}'),
          onTap: onTap,
          child: SizedBox(
            height: 112 * MediaQuery.textScalerOf(context).scale(14) / 14,
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  height: double.infinity,
                  child: ColoredBox(
                    color: colors.primary.withValues(alpha: .06),
                    child: Icon(
                      questionIcon(option.symbol),
                      key: ValueKey('question-icon-${option.id}'),
                      color: colors.primary,
                      size: 32,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          option.title,
                          maxLines: option.description == null ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            height: 1.35,
                          ),
                        ),
                        if (option.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            option.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    selected ? Icons.check_circle : Icons.chevron_right,
                    color: selected ? colors.primary : colors.outline,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData questionIcon(CuriositySymbol symbol) => switch (symbol) {
  CuriositySymbol.dining => Icons.restaurant_outlined,
  CuriositySymbol.explore => Icons.explore_outlined,
  CuriositySymbol.spa => Icons.spa_outlined,
  CuriositySymbol.celebration => Icons.celebration_outlined,
  CuriositySymbol.bakery => Icons.bakery_dining_outlined,
  CuriositySymbol.history => Icons.account_balance_outlined,
  CuriositySymbol.craft => Icons.handyman_outlined,
  CuriositySymbol.water => Icons.water_outlined,
  CuriositySymbol.walking => Icons.hiking_outlined,
  CuriositySymbol.railway => Icons.train_outlined,
  CuriositySymbol.landscape => Icons.landscape_outlined,
  CuriositySymbol.town => Icons.location_city_outlined,
};
