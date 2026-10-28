import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../service/curiosity_questions.dart';
import '../../model/experience.dart';
import '../../state/discovery_state.dart';
import '../../state/experience_photos.dart';
import '../../state/trip_state.dart';
import '../../widgets/travel_photo.dart';
import 'experience_detail.dart';

class ExperienceDeck extends HookConsumerWidget {
  const ExperienceDeck({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryProvider);
    final trip = ref.watch(tripProvider);
    final photos = ref.watch(experiencePhotosProvider);
    return photos.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('旅の写真をまとめて準備しています…'),
          ],
        ),
      ),
      error: (_, stack) => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(experiencePhotosProvider),
          child: const Text('写真を読み込み直す'),
        ),
      ),
      data: (images) {
        if (discovery.index >= discovery.deck.length) {
          return Center(
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
                    '${trip.saved.length}件の体験を保存しました。\n「旅を組み立てる」から、自分だけの一日へ。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () =>
                        ref.read(discoveryProvider.notifier).reset(),
                    child: const Text('ホームへ戻る'),
                  ),
                ],
              ),
            ),
          );
        }
        return _SwipeExperienceCards(
          key: ValueKey(discovery.deck.map((e) => e.id).join(',')),
          images: images,
        );
      },
    );
  }
}

class _SwipeExperienceCards extends HookConsumerWidget {
  final Map<String, ImageInfo?> images;
  const _SwipeExperienceCards({super.key, required this.images});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryProvider);
    final trip = ref.watch(tripProvider);
    final hints = CuriosityQuestions.hints(discovery.interests);
    final dismissalVersion = useState(0);
    Widget card(int index) {
      final e = discovery.deck[index];
      final image = images[e.id];
      return _ExperienceCard(
        experience: e,
        photo: image == null
            ? PhotoPlaceholder(e)
            : RawImage(image: image.image, fit: BoxFit.cover),
        number: '${index + 1} / ${discovery.deck.length}',
        detour: !hints.closeGenres.contains(e.category) && index % 3 == 2,
        closeToMood: hints.closeGenres.contains(e.category),
        saved: trip.contains(e),
        onSave: () => ref.read(tripProvider.notifier).save(e),
        onSkip: () => ref.read(discoveryProvider.notifier).advance(),
      );
    }

    final index = discovery.index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (discovery.deck.length > 1)
              ExcludeSemantics(
                child: IgnorePointer(
                  child: card((index + 1) % discovery.deck.length),
                ),
              ),
            Dismissible(
              key: ValueKey(
                'experience-$index-${dismissalVersion.value}-${trip.saved.length}',
              ),
              direction: DismissDirection.horizontal,
              resizeDuration: null,
              onDismissed: (direction) {
                if (direction == DismissDirection.startToEnd) {
                  ref.read(tripProvider.notifier).save(discovery.deck[index]);
                }
                dismissalVersion.value++;
                ref.read(discoveryProvider.notifier).advance();
              },
              child: card(index),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExperienceCard extends HookConsumerWidget {
  final Experience experience;
  final Widget photo;
  final String number;
  final bool detour, closeToMood, saved;
  final VoidCallback onSave, onSkip;
  const _ExperienceCard({
    required this.experience,
    required this.photo,
    required this.number,
    required this.detour,
    required this.closeToMood,
    required this.saved,
    required this.onSave,
    required this.onSkip,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    onLongPress: () => showExperience(context, experience),
    child: Stack(
      fit: StackFit.expand,
      children: [
        photo,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black38, Colors.transparent, Colors.black87],
              stops: [0, .3, 1],
            ),
          ),
        ),
        Positioned(
          top: 14,
          left: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      detour
                          ? '寄り道の発見'
                          : closeToMood
                          ? 'いまの気分に近い体験'
                          : '興味がつながる体験',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(number, style: const TextStyle(color: Colors.white)),
                ],
              ),
              if (detour)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'こんな世界も、ちょっと覗いてみませんか？',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          left: 22,
          right: 22,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '⌖ ${experience.area}  ·  #${experience.category}',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                experience.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  height: 1.35,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                experience.description,
                style: const TextStyle(color: Colors.white, height: 1.6),
              ),
              const SizedBox(height: 10),
              const Text(
                '写真はイメージ / 体験内容はサンプル',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: '次の体験へ',
                    onPressed: onSkip,
                    icon: const Icon(Icons.arrow_forward, color: Colors.white),
                  ),
                  TextButton(
                    onPressed: () => showExperience(context, experience),
                    child: const Text(
                      '長押し・タップで詳しく',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: '体験を保存',
                    onPressed: onSave,
                    icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
                  ),
                ],
              ),
              const Center(
                child: Text(
                  '← 次の体験  /  右スワイプで保存 →',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
