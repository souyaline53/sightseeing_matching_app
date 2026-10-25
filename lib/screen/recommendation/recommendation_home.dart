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
    final discovery = ref.watch(discoveryProvider);
    final controller = ref.read(discoveryProvider.notifier);
    final step = discovery.step,
        mood = discovery.mood,
        question = discovery.question;
    Widget moodScreen(BuildContext context) => LayoutBuilder(
      key: const ValueKey('moods'),
      builder: (context, constraints) {
        final cardHeight = ((constraints.maxHeight - 140) / 3).clamp(
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
                '明日、どこにいきたい？',
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
                  label: moods[i].$1,
                  child: Material(
                    color: Colors.white,
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
      final food = moods[mood].$2 == '食';
      final labels = question == 0
          ? (food
                ? ['誰もが知る、とびきりおいしいもの', '地元の人しか知らない、秘密の味']
                : ['みんなに愛される、定番の体験', 'まだ知らない、路地の向こう'])
          : ['作り手や土地の物語を知りたい', '偶然の発見に、身をまかせたい'];
      return SingleChildScrollView(
        key: ValueKey('question$question'),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: (question + 1) / 2),
            const SizedBox(height: 24),
            Text('直感のヒント  ${question + 1} / 2'),
            const SizedBox(height: 16),
            const Text(
              'どちらに惹かれる？',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('正解はありません。心が動くほうへ。'),
            const SizedBox(height: 24),
            for (var i = 0; i < 2; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => controller.answer(i),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 150,
                          child: TravelPhoto(
                            experiences[question == 0
                                ? (i == 0 ? 0 : 3)
                                : (i == 0 ? 4 : 2)],
                          ),
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

    return Scaffold(
      appBar: AppBar(
        leading: step > 0
            ? IconButton(
                tooltip: '気分を選び直す',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => controller.reset(),
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
                '0${step + 1} / 03',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: step == 0
            ? moodScreen(context)
            : step == 1
            ? questions(context)
            : const ExperienceDeck(),
      ),
    );
  }
}
