import 'dart:typed_data';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../data/catalog_data.dart';
import '../model/post.dart';
import '../model/account_profile.dart';
import '../repository/posts_repository.dart';
import '../repository/firestore_posts_repository.dart';
import '../repository/cloud_image_repository.dart';
import '../service/image_policy.dart';
import '../service/cloud/cloud_services.dart';
import 'account_state.dart';

final postsRepositoryProvider = Provider<PostsRepository>(
  (ref) =>
      FirestorePostsRepository(() => ref.read(cloudServicesProvider.future)),
);
final postsProvider = StreamNotifierProvider<PostsNotifier, PostsState>(
  PostsNotifier.new,
);

class PostsNotifier extends StreamNotifier<PostsState> {
  @override
  Stream<PostsState> build() => ref.watch(postsRepositoryProvider).watch();
  void reload() => ref.invalidateSelf();
  Future<CurrentAccount> _account() async {
    final repository = await ref.read(accountRepositoryProvider.future);
    final identity = await repository.watchIdentity().first;
    final current = ref.read(currentAccountProvider);
    return CurrentAccount(
      identity: identity,
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
    final catalog = await ref.read(catalogProvider.future);
    if (!catalog.experiences.any((e) => e.id == spotId)) {
      throw StateError('訪れた場所を選択してください。');
    }
    if (caption.trim().isEmpty) throw StateError('本文を入力してください。');
    if (caption.length > 2000) throw StateError('本文は2,000文字以内で入力してください。');
    if (category.isEmpty || !rating.isFinite || rating < 1 || rating > 5) {
      throw StateError('評価とカテゴリを選択してください。');
    }
    if (media.isEmpty || media.length > 6) {
      throw StateError('画像を1〜6枚選択してください。');
    }
    if (media.map((e) => e.id).toSet().length != media.length) {
      throw StateError('メディアが重複しています。');
    }
    for (final item in media) {
      if (bytes[item.id] == null) {
        throw StateError('画像を選択し直してください。動画は投稿できません。');
      }
      await validateImage(bytes[item.id]!);
    }
    final images = ref.read(cloudImageRepositoryProvider);
    final owner = await images.postOwner();
    final id = newPostId('post');
    final uploaded = <PostMedia>[];
    try {
      for (final image in media) {
        final result = await images.upload(
          'posts/$owner/$id/${image.id}',
          bytes[image.id]!,
        );
        uploaded.add(
          PostMedia(
            id: image.id,
            source: result.url,
            storagePath: result.path,
            mimeType: 'image/jpeg',
          ),
        );
      }
      final account = await _account();
      if (account.identity.uid != owner) {
        throw StateError('ログイン状態が変わりました。もう一度投稿してください。');
      }
      final post = TravelPost(
        id: id,
        userId: owner,
        userName: account.name,
        spotId: spotId,
        category: category,
        caption: caption.trim(),
        media: uploaded,
        rating: rating,
        createdAt: DateTime.now(),
      );
      await ref.read(postsRepositoryProvider).create(post);
    } catch (_) {
      for (final image in uploaded) {
        try {
          await images.delete(image.storagePath);
        } catch (_) {
          /* 再接続後にStorageで未参照ファイルを確認する。 */
        }
      }
      rethrow;
    }
  }

  Future<void> toggleLike(String id) =>
      ref.read(postsRepositoryProvider).toggleLike(id);
  Future<void> toggleSaved(String id) =>
      ref.read(postsRepositoryProvider).toggleSaved(id);
  Future<void> toggleFollow(String userId) =>
      ref.read(postsRepositoryProvider).toggleFollow(userId);
  Future<void> comment(String postId, String text) async {
    if (text.trim().isEmpty || text.length > 500) {
      throw StateError('コメントは1〜500文字で入力してください。');
    }
    final uid = await ref.read(cloudImageRepositoryProvider).postOwner();
    final account = await _account();
    if (account.identity.uid != uid) throw StateError('ログイン状態が変わりました。');
    await ref
        .read(postsRepositoryProvider)
        .addComment(
          postId,
          PostComment(
            id: newPostId('comment'),
            userId: uid,
            userName: account.name,
            text: text.trim(),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> delete(String id) async {
    final current = await future;
    final account = await _account();
    final post = current.posts.where((e) => e.id == id).firstOrNull;
    if (post == null || account.identity.uid != post.userId) {
      throw StateError('自分の投稿だけ削除できます。');
    }
    await ref.read(postsRepositoryProvider).delete(post);
    for (final image in post.media) {
      try {
        await ref.read(cloudImageRepositoryProvider).delete(image.storagePath);
      } catch (_) {
        throw StateError('投稿は削除済みですが、写真の削除に失敗しました。Storageを確認してください。');
      }
    }
  }
}
