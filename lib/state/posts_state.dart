import 'dart:async';
import 'dart:typed_data';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../data/mock_data.dart';
import '../model/experience.dart';
import '../model/account_profile.dart';
import 'account_state.dart';
import '../model/post.dart';
import '../repository/posts_repository.dart';

final postsRepositoryProvider = Provider<PostsRepository>((ref) {
  final repository = LocalPostsRepository();
  ref.onDispose(() => unawaited(repository.close()));
  return repository;
});
final postsProvider = AsyncNotifierProvider<PostsNotifier, PostsState>(
  PostsNotifier.new,
);
final postMediaBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>(
      (ref, id) => ref.watch(postsRepositoryProvider).readMedia(id),
    );

class PostsNotifier extends AsyncNotifier<PostsState> {
  Future<void> _queue = Future.value();
  @override
  Future<PostsState> build() async {
    final repository = ref.read(postsRepositoryProvider);
    final saved = await repository.load();
    if (saved != null) return saved;
    final catalog = await ref.watch(mockCatalogProvider.future);
    final initial = _samplePosts(catalog.experiences);
    await repository.save(initial);
    return initial;
  }

  Future<void> _update(
    PostsState Function(PostsState) change, {
    Map<String, Uint8List> media = const {},
    Set<String> removeMedia = const {},
  }) {
    final operation = _queue.then((_) async {
      final current = await future;
      final next = change(current);
      await ref
          .read(postsRepositoryProvider)
          .save(next, media: media, removeMedia: removeMedia);
      if (ref.mounted) state = AsyncData(next);
    });
    _queue = operation.then(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }

  Future<CurrentAccount> _account() async {
    final repository = await ref.read(accountRepositoryProvider.future);
    final identity = await repository.watchIdentity().first;
    final guest = await ref.read(guestIdentityProvider.future);
    final current = ref.read(currentAccountProvider);
    return CurrentAccount(
      identity: identity,
      guest: guest,
      details: current.identity.uid == identity.uid ? current.details : null,
    );
  }

  Future<void> publish({
    required String spotId,
    required String caption,
    required String category,
    required double rating,
    required List<PostMedia> media,
    Map<String, Uint8List> bytes = const {},
  }) async {
    final catalog = await ref.read(mockCatalogProvider.future);
    if (!catalog.experiences.any((e) => e.id == spotId)) {
      throw StateError('訪れた場所を選択してください。');
    }
    if (caption.trim().isEmpty) throw StateError('本文を入力してください。');
    if (caption.length > 2000) throw StateError('本文は2,000文字以内で入力してください。');
    if (category.isEmpty || !rating.isFinite || rating < 1 || rating > 5) {
      throw StateError('評価とカテゴリを選択してください。');
    }
    if (media.isEmpty || media.length > 6) {
      throw StateError('写真・動画を1〜6件選択してください。');
    }
    if (media.map((e) => e.id).toSet().length != media.length) {
      throw StateError('メディアが重複しています。');
    }
    for (final item in media) {
      if (item.isLocal && (bytes[item.id] == null || bytes[item.id]!.isEmpty)) {
        throw StateError('写真・動画を読み直してください。');
      }
    }
    if (bytes.values.fold<int>(0, (total, data) => total + data.length) >
        40 * 1024 * 1024) {
      throw StateError('投稿のメディアは合計40MBまでです。');
    }
    final account = await _account();
    final post = TravelPost(
      id: newPostId('post'),
      userId: account.identity.uid,
      userName: account.name,
      spotId: spotId,
      category: category,
      caption: caption.trim(),
      media: media,
      rating: rating,
      createdAt: DateTime.now(),
    );
    await _update(
      (current) => current.copyWith(posts: [post, ...current.posts]),
      media: bytes,
    );
  }

  Future<void> toggleLike(String id) => _update((current) {
    final liked = {...current.likedIds};
    final remove = liked.remove(id);
    if (!remove) liked.add(id);
    return current.copyWith(
      likedIds: liked,
      posts: [
        for (final p in current.posts)
          p.id == id
              ? p.copyWith(
                  likeCount: (p.likeCount + (remove ? -1 : 1)).clamp(
                    0,
                    1 << 30,
                  ),
                )
              : p,
      ],
    );
  });
  Future<void> toggleSaved(String id) => _update((current) {
    final saved = {...current.savedIds};
    if (!saved.remove(id)) saved.add(id);
    return current.copyWith(savedIds: saved);
  });
  Future<void> toggleFollow(String userId) async {
    final account = await _account();
    if (account.ownsPost(userId)) return;
    await _update((current) {
      final following = {...current.followingIds};
      if (!following.remove(userId)) following.add(userId);
      return current.copyWith(followingIds: following);
    });
  }

  Future<void> comment(String postId, String text) async {
    if (text.trim().isEmpty || text.length > 500) {
      throw StateError('コメントは1〜500文字で入力してください。');
    }
    final account = await _account();
    final comment = PostComment(
      id: newPostId('comment'),
      userId: account.identity.uid,
      userName: account.name,
      text: text.trim(),
      createdAt: DateTime.now(),
    );
    await _update(
      (current) => current.copyWith(
        posts: [
          for (final post in current.posts)
            post.id == postId
                ? post.copyWith(comments: [...post.comments, comment])
                : post,
        ],
      ),
    );
  }

  Future<void> delete(String id) async {
    final account = await _account();
    final current = await future;
    final post = current.posts.where((e) => e.id == id).firstOrNull;
    if (post == null || !account.ownsPost(post.userId)) {
      throw StateError('自分の投稿だけ削除できます。');
    }
    final remove = post.media
        .where((m) => m.isLocal)
        .map((m) => m.id)
        .where(
          (mediaId) => !current.posts.any(
            (p) => p.id != id && p.media.any((m) => m.id == mediaId),
          ),
        )
        .toSet();
    await _update(
      (data) => data.copyWith(
        posts: data.posts.where((p) => p.id != id).toList(),
        likedIds: {...data.likedIds}..remove(id),
        savedIds: {...data.savedIds}..remove(id),
      ),
      removeMedia: remove,
    );
    for (final id in remove) {
      ref.invalidate(postMediaBytesProvider(id));
    }
  }
}

PostsState _samplePosts(List<Experience> spots) {
  final now = DateTime.now().toUtc();
  final posts = <TravelPost>[];
  final ids = ['melon', 'lake', 'otaru'];
  final names = ['はる｜週末の寄り道', 'ゆき｜北海道さんぽ', 'そう｜小さな冒険'];
  final captions = [
    'ひとくちの甘さから、土地の物語が気になった日。次は街の歴史にも寄り道してみたい。\n#夕張 #旅の発見 #グルメ',
    '予定を詰めない休日。水面を眺めているだけで、気持ちがほどける。\n#北海道 #自然 #リフレッシュ',
    'いつもの道から一本それたら、まだ知らない景色に出会えた。\n#小樽 #街歩き #週末旅',
  ];
  for (var i = 0; i < ids.length; i++) {
    final spot = spots.where((e) => e.id == ids[i]).firstOrNull;
    if (spot == null) continue;
    final photos = [spot.photo, ...spot.additionalPhotos];
    final related = spots
        .where(
          (e) => e.id != spot.id && e.area.contains(spot.area.split('・').first),
        )
        .firstOrNull;
    if (related != null && photos.length == 1) photos.add(related.photo);
    posts.add(
      TravelPost(
        id: 'sample-post-$i',
        userId: 'sample-user-$i',
        userName: names[i],
        avatar: spot.photo,
        spotId: spot.id,
        category: i == 0
            ? 'グルメ'
            : i == 1
            ? '絶景'
            : '街歩き',
        caption: captions[i],
        media: [
          for (var j = 0; j < photos.length; j++)
            PostMedia(id: 'sample-$i-$j', source: photos[j]),
        ],
        rating: [4.5, 5.0, 4.0][i],
        createdAt: now.subtract(Duration(hours: 2 + i * 5)),
        likeCount: [24, 38, 17][i],
        comments: [
          PostComment(
            id: 'sample-comment-$i',
            userId: 'sample-visitor',
            userName: 'みどり',
            text: 'こんな寄り道もいいですね！',
            createdAt: now.subtract(Duration(hours: 1 + i)),
          ),
        ],
      ),
    );
  }
  return PostsState(posts: posts, followingIds: {'sample-user-0'});
}
