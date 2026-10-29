import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/posts_state.dart';
import 'widgets/post_card.dart';

class SpotReviews extends HookConsumerWidget {
  final String spotId;
  const SpotReviews({super.key, required this.spotId});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(postsProvider)
      .when(
        loading: () => const Padding(
          padding: EdgeInsets.only(top: 24),
          child: LinearProgressIndicator(),
        ),
        error: (_, stack) => TextButton(
          onPressed: () => ref.invalidate(postsProvider),
          child: const Text('みんなのレビューを読み込み直す'),
        ),
        data: (state) {
          final posts =
              state.posts.where((post) => post.spotId == spotId).toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return Column(
            key: ValueKey('spot-reviews-$spotId'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 28),
              Text(
                'みんなのレビュー（${posts.length}件）',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (posts.isEmpty)
                const Text('この場所の投稿はまだありません。', style: TextStyle(fontSize: 13))
              else ...[
                Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 19,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    Text(
                      ' ${(posts.fold<double>(0, (n, p) => n + p.rating) / posts.length).toStringAsFixed(1)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                for (final post in posts.take(3))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${post.userName} · ★${post.rating.toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      post.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => _SpotReviewPosts(spotId: spotId),
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => _SpotReviewPosts(spotId: spotId),
                    ),
                  ),
                  child: const Text('投稿をすべて見る'),
                ),
              ],
            ],
          );
        },
      );
}

class _SpotReviewPosts extends HookConsumerWidget {
  final String spotId;
  const _SpotReviewPosts({required this.spotId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref
        .watch(postsProvider)
        .requireValue
        .posts
        .where((p) => p.spotId == spotId)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('みんなのレビュー')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          for (final post in posts)
            PostCard(key: ValueKey(post.id), post: post),
        ],
      ),
    );
  }
}
