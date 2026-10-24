import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../model/experience.dart';
import '../../state/trip_state.dart';
import '../../widgets/travel_photo.dart';
import 'experience_detail.dart';

class RecommendationHome extends StatefulWidget {
  final TripState trip;
  const RecommendationHome({super.key, required this.trip});
  @override
  State<RecommendationHome> createState() => _RecommendationHomeState();
}

class _RecommendationHomeState extends State<RecommendationHome> {
  int step = 0, mood = 0, question = 0, index = 0;
  final answers = <int>[];
  List<Experience> deck = [];
  void advance(bool save) {
    if (index >= deck.length) return;
    if (save) widget.trip.save(deck[index]);
    setState(() => index++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: step > 0
          ? IconButton(
              tooltip: '気分を選び直す',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                step = 0;
                question = 0;
                answers.clear();
              }),
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
          : explore(context),
    ),
  );
  Widget moodScreen(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('moods'),
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'いつもの日常に、ちょっと冒険を。',
          style: TextStyle(color: Color(0xff145c49), fontSize: 12),
        ),
        const SizedBox(height: 12),
        const Text(
          '明日、どんな気持ちに\nなりたい？',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.bold,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text('直感でひとつ、選んでみてください。'),
        const SizedBox(height: 24),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: moods.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: .84,
          ),
          itemBuilder: (context, i) => Semantics(
            selected: mood == i,
            child: InkWell(
              onTap: () => setState(() => mood = i),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: mood == i
                        ? const Color(0xff145c49)
                        : const Color(0xffe3e7e3),
                    width: mood == i ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
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
                          if (mood == i)
                            const Positioned(
                              top: 8,
                              right: 8,
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        moods[i].$1,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => setState(() => step = 1),
            child: const Text('この気分で、出かけよう  →'),
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'まだ知らないワクワクを、自分だけの旅に。',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    ),
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
                  onTap: () => setState(() {
                    answers.add(i);
                    if (question == 0) {
                      question++;
                    } else {
                      deck = recommend(moods[mood].$2, answers);
                      index = 0;
                      step = 2;
                    }
                  }),
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

  Widget explore(BuildContext context) {
    if (index >= deck.length) {
      return Center(
        key: const ValueKey('end'),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, size: 48),
              const SizedBox(height: 20),
              const Text('気になる旅は、見つかりましたか？', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                '${widget.trip.saved.length}件の体験を保存しました。\n「旅を組み立てる」から、自分だけの一日へ。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => setState(() => index = 0),
                child: const Text('もう一度、体験を見る'),
              ),
            ],
          ),
        ),
      );
    }
    final e = deck[index];
    final detour = e.category != moods[mood].$2 && index % 3 == 2;
    return Padding(
      key: const ValueKey('explore'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'あなたの好奇心を、ひとつ先へ。',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text('${index + 1} / ${deck.length}'),
            ],
          ),
          const SizedBox(height: 10),
          if (detour)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                '寄り道 ✧ こんな世界も、ちょっと覗いてみませんか？',
                style: TextStyle(color: Color(0xff145c49), fontSize: 12),
              ),
            ),
          Expanded(
            child: Dismissible(
              key: ValueKey('${e.id}-$index'),
              direction: DismissDirection.horizontal,
              onDismissed: (direction) =>
                  advance(direction == DismissDirection.startToEnd),
              background: const Center(
                child: Icon(Icons.favorite, size: 72, color: Color(0xff145c49)),
              ),
              secondaryBackground: const Center(
                child: Icon(Icons.arrow_forward, size: 72, color: Colors.grey),
              ),
              child: GestureDetector(
                onLongPress: () => showExperience(context, e, widget.trip),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TravelPhoto(e),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                            stops: [.25, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 16,
                        left: 16,
                        child: Chip(
                          label: Text(
                            detour
                                ? '寄り道の発見'
                                : e.category == moods[mood].$2
                                ? 'いまの気分に近い体験'
                                : '興味がつながる体験',
                          ),
                        ),
                      ),
                      Positioned(
                        left: 22,
                        right: 22,
                        bottom: 24,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⌖ ${e.area}  ·  #${e.category}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              e.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 27,
                                height: 1.4,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              e.description,
                              style: const TextStyle(
                                color: Colors.white,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '写真はイメージ / 体験内容はサンプル',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
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
          const SizedBox(height: 10),
          const Text(
            '← 次の体験へ  /  右スワイプで保存 →',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton.filledTonal(
                tooltip: '次の体験へ',
                onPressed: () => advance(false),
                icon: const Icon(Icons.close),
              ),
              TextButton(
                onPressed: () => showExperience(context, e, widget.trip),
                child: const Text('詳しく見る'),
              ),
              IconButton.filled(
                tooltip: '体験を保存',
                onPressed: () => advance(true),
                icon: Icon(
                  widget.trip.contains(e)
                      ? Icons.favorite
                      : Icons.favorite_border,
                ),
              ),
            ],
          ),
          const Text(
            'カードを長押しで詳しく見る',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
