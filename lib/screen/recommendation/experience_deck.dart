import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/experience.dart';
import '../../state/discovery_state.dart';
import '../../state/experience_photos.dart';
import '../../state/trip_state.dart';
import '../../state/settings_state.dart';
import '../../widgets/travel_photo.dart';
import 'experience_detail.dart';
import '../search/search_filter_sheet.dart';
import 'swipe_tips_animation.dart';

class ExperienceDeck extends HookConsumerWidget {
  const ExperienceDeck({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryProvider);
    if (discovery.aiLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, size: 27, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text('AIがあなたに合う体験を探しています…\nもう少しで完了します…'),
              ],
            ),
          ],
        )
      );
    }
    if (discovery.aiError != null || discovery.deck.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(discovery.aiError ?? '条件に合う推薦結果がありませんでした。'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref
                    .read(discoveryProvider.notifier)
                    .showExplore(retry: true),
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
      );
    }
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
        return _SwipeExperienceCards(
          key: ValueKey(discovery.deck.map((e) => e.id).join(',')),
          images: images,
        );
      },
    );
  }
}

class _DeckCompletion extends HookConsumerWidget {
  const _DeckCompletion();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 48),
            const SizedBox(height: 20),
            const Text('すべての観光地を見終わりました', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              '${trip.saved.length}件の体験を保存しました。\n「旅を組み立てる」から、自分だけの一日へ。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => ref.read(discoveryProvider.notifier).goTo(0),
              child: const Text('最初のカードに戻る'),
            ),
            FilledButton(
              onPressed: () => showSearchFilterSheet(context),
              child: const Text('条件を変更して再検索'),
            ),
          ],
        ),
      ),
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
    final settings = ref.watch(settingsProvider);
    final tipsRequested = useRef(false);
    final pages = usePageController(initialPage: discovery.index);
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted &&
            pages.hasClients &&
            pages.page!.round() != discovery.index) {
          pages.jumpToPage(discovery.index);
        }
      });
      return null;
    }, [discovery.index]);
    void next(int index) {
      pages.animateToPage(
        index + 1,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }

    useEffect(() {
      if (settings.hasValue &&
          !settings.requireValue.experienceTipsSeen &&
          !tipsRequested.value) {
        tipsRequested.value = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) _showExperienceTips(context, ref);
        });
      }
      return null;
    }, [settings.hasValue]);

    Widget card(int index) {
      final e = discovery.deck[index];
      final image = images[e.id];
      return _ExperienceCard(
        experience: e,
        photo: image == null
            ? PhotoPlaceholder(e)
            : RawImage(image: image.image, fit: BoxFit.cover),
        number: '${index + 1} / ${discovery.deck.length}',
        reason: discovery.recommendationReasons[e.id] ?? '',
        saved: trip.contains(e),
        onSave: () => ref.read(tripProvider.notifier).toggle(e),
        onSkip: () => next(index),
      );
    }

    return PageView.builder(
      key: const ValueKey('experience-pages'),
      controller: pages,
      itemCount: discovery.deck.length + 1,
      onPageChanged: (index) =>
          ref.read(discoveryProvider.notifier).goTo(index),
      itemBuilder: (context, index) {
        if (index == discovery.deck.length) return const _DeckCompletion();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Dismissible(
              key: ValueKey('experience-page-$index'),
              direction: DismissDirection.up,
              background: ColoredBox(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.favorite_border,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '保存する',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              resizeDuration: null,
              confirmDismiss: (_) async {
                ref.read(tripProvider.notifier).save(discovery.deck[index]);
                pages.jumpToPage(index + 1);
                // Keep the page available when swiping back to this saved card.
                return false;
              },
              child: card(index),
            ),
          ),
        );
      },
    );
  }
}

class _ExperienceCard extends HookConsumerWidget {
  final Experience experience;
  final Widget photo;
  final String number;
  final bool saved;
  final String reason;
  final VoidCallback onSave, onSkip;
  const _ExperienceCard({
    required this.experience,
    required this.photo,
    required this.number,
    required this.reason,
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
                      'あなたへのおすすめ',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(number, style: const TextStyle(color: Colors.white)),
                  IconButton(
                    tooltip: 'スワイプのヒント',
                    onPressed: () => _showExperienceTips(context, ref),
                    icon: const Icon(Icons.help_outline, color: Colors.white),
                  ),
                ],
              ),
              if (reason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    reason,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
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
                '⌖ ${experience.area} ·  #${experience.category}',
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
                experience.name,
                style: const TextStyle(color: Colors.white, height: 1.6),
              ),
              SizedBox(height: 20),
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
                      '詳しく見る',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: saved ? '保存を取り消す' : '体験を保存',
                    onPressed: onSave,
                    icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> _showExperienceTips(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider.notifier);
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => AlertDialog(
      title: const Text('観光地カードの楽しみ方'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwipeTipsAnimation(),
            SizedBox(height: 16),
            Text('← 左にスワイプ：次の観光地へ'),
            SizedBox(height: 12),
            Text('→ 右にスワイプ：前の観光地へ'),
            SizedBox(height: 12),
            Text('↑ 上にスワイプ：保存して次へ'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('はじめる'),
        ),
      ],
    ),
  );
  try {
    await settings.markExperienceTipsSeen();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('確認状態を保存できませんでした。')));
    }
  }
}
