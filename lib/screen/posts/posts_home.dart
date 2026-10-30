import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/catalog_data.dart';
import '../../model/post.dart';
import '../../service/curiosity_questions.dart';
import '../../state/discovery_state.dart';
import '../../state/posts_state.dart';
import '../../state/account_state.dart';
import '../recommendation/experience_detail.dart';
import 'post_create_screen.dart';
import 'widgets/post_card.dart';

class PostsHome extends HookConsumerWidget {
  const PostsHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final social = ref.watch(postsProvider);
    final account = ref.watch(currentAccountProvider);
    final tabs = useTabController(initialLength: 2);
    final recommendedScroll = useScrollController();
    final followingScroll = useScrollController();
    final opening = useState(false);
    final colors = Theme.of(context).colorScheme;
    final interests = ref.watch(
      discoveryProvider.select((state) => state.interests),
    );
    final hints = CuriosityQuestions.hints(interests);
    final spots = ref.watch(catalogProvider).requireValue.experiences;
    Future<void> compose() async {
      if (opening.value) return;
      opening.value = true;
      try {
        final published = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const PostCreateScreen()),
        );
        if (published == true && context.mounted) {
          tabs.animateTo(0);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (recommendedScroll.hasClients) recommendedScroll.jumpTo(0);
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('投稿しました。')));
        }
      } finally {
        if (context.mounted) opening.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('投稿'),
        actions: [
          IconButton(
            tooltip: '保存した投稿',
            onPressed: social.hasValue
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const SavedPostsScreen(),
                    ),
                  )
                : null,
            icon: const Icon(Icons.bookmarks_outlined),
          ),
        ],
        bottom: TabBar(
          controller: tabs,
          tabs: const [
            Tab(text: 'おすすめ'),
            Tab(text: 'フォロー中'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '投稿を作成',
        onPressed: opening.value || !social.hasValue ? null : compose,
        child: const Icon(Icons.add),
      ),
      body: social.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '投稿を読み込めませんでした。Firebaseの設定と通信を確認してください。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.read(postsProvider.notifier).reload(),
                  child: const Text('再読み込み'),
                ),
              ],
            ),
          ),
        ),
        data: (data) {
          int priority(TravelPost post) {
            if (account.ownsPost(post.userId)) return -1;
            final category = spots
                .where((e) => e.id == post.spotId)
                .firstOrNull
                ?.category;
            if (hints.questGenres.contains(category)) return 0;
            if (hints.closeGenres.contains(category)) return 1;
            return 2;
          }

          final recommended = [...data.posts]
            ..sort((a, b) {
              final order = priority(a).compareTo(priority(b));
              return order != 0 ? order : b.createdAt.compareTo(a.createdAt);
            });
          final following =
              data.posts
                  .where((p) => data.followingIds.contains(p.userId))
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          Widget feed(
            List<TravelPost> posts,
            ScrollController controller,
            bool followed,
          ) {
            if (posts.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        followed
                            ? Icons.people_outline
                            : Icons.photo_library_outlined,
                        color: colors.primary,
                        size: 48,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        followed ? 'フォロー中の投稿はまだありません' : '最初の旅の発見を投稿してみましょう',
                        textAlign: TextAlign.center,
                      ),
                      if (followed) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'おすすめの投稿メニューからフォローできます。',
                          style: TextStyle(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        TextButton(
                          onPressed: () => tabs.animateTo(0),
                          child: const Text('おすすめを見る'),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }
            return ListView.builder(
              controller: controller,
              key: PageStorageKey(
                followed ? 'following-posts' : 'recommended-posts',
              ),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
              itemCount: posts.length + 1,
              itemBuilder: (context, index) => index == 0
                  ? Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 12),
                      child: Text(
                        followed ? 'フォローしているユーザーの投稿' : '質問の回答を参考に表示しています',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : PostCard(
                      key: ValueKey(posts[index - 1].id),
                      post: posts[index - 1],
                      onSpotTap: (spot) => showExperience(context, spot),
                    ),
            );
          }

          return TabBarView(
            controller: tabs,
            children: [
              feed(recommended, recommendedScroll, false),
              feed(following, followingScroll, true),
            ],
          );
        },
      ),
    );
  }
}

class SavedPostsScreen extends HookConsumerWidget {
  const SavedPostsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(postsProvider).requireValue;
    final posts = data.posts
        .where((post) => data.savedIds.contains(post.id))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('保存した投稿')),
      body: posts.isEmpty
          ? const Center(child: Text('しおりアイコンで投稿を保存できます。'))
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                for (final post in posts)
                  PostCard(
                    key: ValueKey(post.id),
                    post: post,
                    onSpotTap: (spot) => showExperience(context, spot),
                  ),
              ],
            ),
    );
  }
}
