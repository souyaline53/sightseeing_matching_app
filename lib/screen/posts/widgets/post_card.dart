import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/mock_data.dart';
import '../../../model/experience.dart';
import '../../../model/post.dart';
import '../../../service/photo_source.dart';
import '../../../state/posts_state.dart';
import '../../../state/account_state.dart';
import '../../../widgets/settings_actions.dart';
import '../comments_sheet.dart';
import 'post_media_view.dart';

String postDateLabel(DateTime date) {
  final local = date.toLocal();
  final difference = DateTime.now().difference(local);
  if (difference.inMinutes < 1) return 'たった今';
  if (difference.inHours < 1) return '${difference.inMinutes}分前';
  if (difference.inDays < 1) return '${difference.inHours}時間前';
  return '${local.year}/${local.month}/${local.day}';
}

class PostAvatar extends HookConsumerWidget {
  final TravelPost post;
  const PostAvatar({super.key, required this.post});
  @override
  Widget build(BuildContext context, WidgetRef ref) => CircleAvatar(
    radius: 20,
    child: post.avatar.isEmpty
        ? const Icon(Icons.person_outline)
        : ClipOval(
            child: Image(
              image: photoSource(post.avatar),
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) =>
                  const Icon(Icons.person_outline),
            ),
          ),
  );
}

enum _PostMenu { follow, copy, delete }

class PostCard extends HookConsumerWidget {
  final TravelPost post;
  final ValueChanged<Experience>? onSpotTap;
  const PostCard({super.key, required this.post, this.onSpotTap});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final social = ref.watch(postsProvider).requireValue;
    final ownPost = ref.watch(currentAccountProvider).ownsPost(post.userId);
    final spot = ref
        .watch(mockCatalogProvider)
        .requireValue
        .experiences
        .where((e) => e.id == post.spotId)
        .firstOrNull;
    final colors = Theme.of(context).colorScheme;
    final page = useState(0);
    final pager = usePageController();
    final busy = useState(false);
    final liked = social.likedIds.contains(post.id),
        saved = social.savedIds.contains(post.id);
    Future<void> perform(Future<void> Function() action) async {
      if (busy.value) return;
      busy.value = true;
      try {
        await action();
      } catch (_) {
        if (context.mounted) showMessage(context, '保存できませんでした。もう一度お試しください。');
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    void comments() {
      ref.read(playingPostVideoProvider.notifier).select(null);
      showPostComments(context, post.id);
    }

    String shareText() =>
        '${spot?.area ?? ''}｜${spot?.title ?? '旅の発見'}\n★${post.rating.toStringAsFixed(1)}\n${post.caption}\n#TABISAKI';
    Future<void> share() async {
      ref.read(playingPostVideoProvider.notifier).select(null);
      final box = context.findRenderObject() as RenderBox?;
      try {
        await SharePlus.instance.share(
          ShareParams(
            text: shareText(),
            subject: 'TABISAKIの旅の発見',
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: shareText()));
        if (context.mounted) showMessage(context, '投稿の本文をコピーしました。');
      }
    }

    Future<void> menu(_PostMenu action) async {
      switch (action) {
        case _PostMenu.follow:
          await perform(
            () => ref.read(postsProvider.notifier).toggleFollow(post.userId),
          );
        case _PostMenu.copy:
          await Clipboard.setData(ClipboardData(text: shareText()));
          if (context.mounted) showMessage(context, '投稿の本文をコピーしました。');
        case _PostMenu.delete:
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('投稿を削除しますか？'),
              content: const Text('この操作は取り消せません。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('削除する'),
                ),
              ],
            ),
          );
          if (confirmed == true && context.mounted) {
            await perform(
              () => ref.read(postsProvider.notifier).delete(post.id),
            );
          }
      }
    }

    return Card(
      key: ValueKey('post-card-${post.id}'),
      margin: const EdgeInsets.only(bottom: 18),
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 4, 0),
            child: Row(
              children: [
                PostAvatar(post: post),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.userName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${postDateLabel(post.createdAt)}${post.userId.startsWith('sample-') ? ' · サンプル投稿' : ''}',
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_PostMenu>(
                  tooltip: '投稿のメニュー',
                  enabled: !busy.value,
                  onSelected: menu,
                  itemBuilder: (_) => [
                    if (!ownPost)
                      PopupMenuItem(
                        value: _PostMenu.follow,
                        child: Text(
                          social.followingIds.contains(post.userId)
                              ? 'フォローを解除'
                              : 'フォローする',
                        ),
                      ),
                    const PopupMenuItem(
                      value: _PostMenu.copy,
                      child: Text('本文をコピー'),
                    ),
                    if (ownPost)
                      PopupMenuItem(
                        value: _PostMenu.delete,
                        child: Text(
                          '投稿を削除',
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 14, 4),
            child: TextButton.icon(
              key: ValueKey('post-spot-${post.id}'),
              onPressed: spot == null || onSpotTap == null
                  ? null
                  : () {
                      ref.read(playingPostVideoProvider.notifier).select(null);
                      onSpotTap!(spot);
                    },
              icon: const Icon(Icons.place_outlined, size: 16),
              label: Text(
                spot == null ? 'スポット未登録' : '${spot.area} · ${spot.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (post.media.isNotEmpty)
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 1.12,
                  child: PageView.builder(
                    key: ValueKey('post-carousel-${post.id}'),
                    controller: pager,
                    itemCount: post.media.length,
                    onPageChanged: (value) => page.value = value,
                    itemBuilder: (_, index) => PostMediaView(
                      key: ValueKey(post.media[index].id),
                      media: post.media[index],
                      active: index == page.value,
                    ),
                  ),
                ),
                if (post.media.length > 1)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${page.value + 1}/${post.media.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          if (post.media.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < post.media.length; i++)
                    Container(
                      width: i == page.value ? 16 : 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i == page.value
                            ? colors.primary
                            : colors.outlineVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                IconButton(
                  key: ValueKey('post-like-${post.id}'),
                  tooltip: liked ? 'いいねを取り消す' : 'いいね',
                  onPressed: busy.value
                      ? null
                      : () => perform(
                          () => ref
                              .read(postsProvider.notifier)
                              .toggleLike(post.id),
                        ),
                  icon: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? colors.primary : null,
                  ),
                ),
                Text('${post.likeCount}', style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'コメント',
                  onPressed: comments,
                  icon: const Icon(Icons.chat_bubble_outline, size: 22),
                ),
                Text(
                  '${post.commentCount}',
                  style: const TextStyle(fontSize: 12),
                ),
                IconButton(
                  tooltip: 'シェア',
                  onPressed: share,
                  icon: const Icon(Icons.ios_share_outlined, size: 22),
                ),
                const Spacer(),
                IconButton(
                  key: ValueKey('post-save-${post.id}'),
                  tooltip: saved ? '投稿の保存を解除' : '投稿を保存',
                  onPressed: busy.value
                      ? null
                      : () => perform(
                          () => ref
                              .read(postsProvider.notifier)
                              .toggleSaved(post.id),
                        ),
                  icon: Icon(
                    saved ? Icons.bookmark : Icons.bookmark_border,
                    color: saved ? colors.primary : null,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.star_rounded, color: colors.primary, size: 19),
                    const SizedBox(width: 4),
                    Text(
                      post.rating.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      post.category,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    children: [
                      for (final part in post.caption.split(
                        RegExp(r'(?=#)|(?<=\s)'),
                      ))
                        TextSpan(
                          text: part,
                          style: part.startsWith('#')
                              ? TextStyle(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600,
                                )
                              : null,
                        ),
                    ],
                  ),
                  key: ValueKey('post-caption-${post.id}'),
                  style: const TextStyle(fontSize: 13, height: 1.65),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: comments,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'コメント${post.commentCount}件を見る',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                if (post.comments.isNotEmpty)
                  Text(
                    '${post.comments.last.userName}  ${post.comments.last.text}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
