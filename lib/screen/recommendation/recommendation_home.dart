import 'package:flutter_hooks/flutter_hooks.dart';
import '../../state/settings_state.dart';
import '../../state/trip_state.dart';
import '../../state/app_tab.dart';
import '../../service/curiosity_questions.dart';
import '../../widgets/settings_actions.dart';
import '../search/search_conditions_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/discovery_state.dart';
import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../widgets/travel_photo.dart';
import 'experience_deck.dart';

class RecommendationHome extends HookConsumerWidget {
  const RecommendationHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = useState(false);
    final settings = ref.watch(settingsProvider).requireValue;
    final discovery = ref.watch(discoveryProvider);
    final controller = ref.read(discoveryProvider.notifier);
    final step = discovery.step,
        mood = discovery.mood,
        question = discovery.question;
    Widget moodScreen(BuildContext context) => LayoutBuilder(
      key: const ValueKey('moods'),
      builder: (context, constraints) {
        final cardHeight = ((constraints.maxHeight - 170) / 3).clamp(
          96.0,
          155.0,
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'いつもの日常に、ちょっと冒険を。',
                style: TextStyle(color: Color(0xff145c49), fontSize: 11),
              ),
              const SizedBox(height: 6),
              const Text(
                '明日、どんな気持ちに\nなりたい？',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text('気になる気分をタップして、出かけよう。', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: moods.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: cardHeight,
                ),
                itemBuilder: (context, i) => Semantics(
                  button: true,
                  selected: mood == i,
                  label: moods[i].$1,
                  child: Material(
                    color: mood == i
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('mood-$i'),
                      onTap: () => controller.selectMood(i),
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                TravelPhoto(
                                  experiences.firstWhere(
                                    (e) => e.category == moods[i].$2,
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: DecoratedBox(
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(5),
                                      child: Icon(
                                        [
                                          Icons.restaurant,
                                          Icons.explore,
                                          Icons.spa,
                                          Icons.people,
                                          Icons.handyman,
                                          Icons.landscape,
                                        ][i],
                                        size: 18,
                                        color: const Color(0xff145c49),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 7,
                            ),
                            child: Text(
                              moods[i].$1,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    Widget questions(BuildContext context) {
      final content = question == 1
          ? CuriosityQuestions.reason(mood)
          : CuriosityQuestions.broaden(
              mood,
              discovery.answers.isEmpty ? 0 : discovery.answers.first,
            );
      final labels = content.choices;
      return SingleChildScrollView(
        key: ValueKey('question$question'),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: (question + 1) / 3),
            const SizedBox(height: 24),
            Text('直感のヒント  ${question + 1} / 3'),
            const SizedBox(height: 16),
            Text(
              content.title,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('正解はありません。心が動くほうへ。'),
            const SizedBox(height: 24),
            for (var i = 0; i < 2; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Card(
                  color:
                      discovery.answers.length >= question &&
                          discovery.answers[question - 1] == i
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: busy.value
                        ? null
                        : () async {
                            controller.answer(i);
                            if (question != 2) return;
                            final conditions = ref.read(searchDraftProvider);
                            final error = conditions.validate();
                            if (error != null) {
                              showMessage(context, error);
                              controller.back();
                              return;
                            }
                            busy.value = true;
                            try {
                              await ref
                                  .read(settingsProvider.notifier)
                                  .saveLast(conditions);
                              if (!context.mounted) return;
                              ref
                                  .read(tripProvider.notifier)
                                  .applyConditions(conditions);
                              controller.showExplore();
                            } catch (_) {
                              if (context.mounted) {
                                showMessage(
                                  context,
                                  '前回条件を保存できませんでした。もう一度選択してください。',
                                );
                              }
                            } finally {
                              if (context.mounted) busy.value = false;
                            }
                          },
                    child: Column(
                      children: [
                        SizedBox(
                          height: 150,
                          child: TravelPhoto(experiences[content.photos[i]]),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  labels[i],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const Icon(Icons.arrow_forward),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (step == 1) return const SearchConditionsScreen();
    if (step == 0) {
      return Scaffold(
        appBar: AppBar(title: const Text('TABISAKI')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.explore_outlined,
                  size: 80,
                  color: Color(0xff145c49),
                ),
                const SizedBox(height: 30),
                const Text(
                  'まだ知らないワクワクを、\n自分だけの旅に。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    height: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('いつもの興味から、思いがけない北海道へ。', textAlign: TextAlign.center),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      ref
                          .read(searchDraftProvider.notifier)
                          .replace(settings.profile.defaults());
                      controller.startConditions();
                    },
                    icon: const Icon(Icons.search),
                    label: const Text('検索を開始する'),
                  ),
                ),
                if (settings.lastSearch != null)
                  TextButton(
                    onPressed: () {
                      ref
                          .read(searchDraftProvider.notifier)
                          .replace(settings.lastSearch!.conditions);
                      controller.startConditions();
                    },
                    child: const Text('前回の条件で探す'),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: step > 0
            ? IconButton(
                tooltip: '前の画面へ',
                icon: const Icon(Icons.arrow_back),
                onPressed: busy.value ? null : () => controller.back(),
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
          if (step == 3)
            IconButton(
              tooltip: '旅行計画へ',
              onPressed: () =>
                  ref.read(appTabProvider.notifier).select(AppTab.itinerary),
              icon: const Icon(Icons.route),
            ),
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
            ? question == 0
                  ? moodScreen(context)
                  : questions(context)
            : const ExperienceDeck(),
      ),
    );
  }
}
