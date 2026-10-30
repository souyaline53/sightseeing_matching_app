import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'package:sightseeing_matching_app/model/post.dart';
import 'package:sightseeing_matching_app/repository/cloud_image_repository.dart';
import 'package:sightseeing_matching_app/state/account_state.dart';
import 'package:sightseeing_matching_app/state/posts_state.dart';
import 'test_support.dart';

void main() {
  initializeCatalogTests();
  ProviderContainer open(
    MemoryPostsRepository repository,
    MemoryCloudImages images,
  ) {
    final container = ProviderContainer(
      overrides: [
        catalogProvider.overrideWith((ref) => Stream.value(testCatalog)),
        postsRepositoryProvider.overrideWithValue(repository),
        cloudImageRepositoryProvider.overrideWithValue(images),
        guestIdentityRepositoryProvider.overrideWithValue(
          MemoryGuestIdentityRepository(),
        ),
        accountRepositoryProvider.overrideWith(
          (ref) => FakeAccountRepository(),
        ),
      ],
    );
    container.listen(postsProvider, (_, _) {});
    container.listen(catalogProvider, (_, _) {});
    addTearDown(container.dispose);
    return container;
  }

  test(
    'new feed is empty; real publication, comment and deletion use repository operations',
    () async {
      final repository = MemoryPostsRepository();
      final images = MemoryCloudImages();
      final container = open(repository, images);
      expect((await container.read(postsProvider.future)).posts, isEmpty);
      final posts = container.read(postsProvider.notifier);
      await posts.publish(
        spotId: 'melon',
        caption: '新しい投稿',
        category: 'グルメ',
        rating: 4,
        media: [const PostMedia(id: 'image', source: '')],
        bytes: {'image': testImageBytes},
      );
      await container.pump();
      final post = repository.value.posts.single;
      expect(post.caption, '新しい投稿');
      expect(post.userId, 'local-user');
      expect(post.media.single.source, startsWith('https://'));
      expect(images.files, hasLength(1));
      await posts.toggleLike(post.id);
      await posts.toggleSaved(post.id);
      await posts.toggleFollow('another-user');
      await posts.comment(post.id, 'コメント');
      await container.pump();
      expect(
        container.read(postsProvider).requireValue.posts.single.commentCount,
        1,
      );
      expect(repository.value.likedIds, contains(post.id));
      expect(repository.value.savedIds, contains(post.id));
      final reopened = open(repository, images);
      expect(
        (await reopened.read(postsProvider.future)).posts.single.caption,
        post.caption,
      );
      expect(
        reopened
            .read(postsProvider)
            .requireValue
            .posts
            .single
            .comments
            .single
            .text,
        'コメント',
      );
      await posts.delete(post.id);
      await container.pump();
      expect(repository.value.posts, isEmpty);
      expect(images.files, isEmpty);
    },
  );
  test(
    'failed cloud create keeps feed and removes newly uploaded photos',
    () async {
      final repository = MemoryPostsRepository()..failWrite = true;
      final images = MemoryCloudImages();
      final container = open(repository, images);
      await container.read(postsProvider.future);
      await expectLater(
        container
            .read(postsProvider.notifier)
            .publish(
              spotId: 'melon',
              caption: '保存失敗',
              category: 'グルメ',
              rating: 5,
              media: [const PostMedia(id: 'image', source: '')],
              bytes: {'image': testImageBytes},
            ),
        throwsStateError,
      );
      expect(repository.value.posts, isEmpty);
      expect(images.files, isEmpty);
    },
  );
  test('invalid input is rejected before upload or cloud write', () async {
    final repository = MemoryPostsRepository();
    final images = MemoryCloudImages();
    final container = open(repository, images);
    await container.read(postsProvider.future);
    final posts = container.read(postsProvider.notifier);
    for (final spot in ['unknown', 'melon']) {
      await expectLater(
        posts.publish(
          spotId: spot,
          caption: ' ',
          category: 'グルメ',
          rating: 5,
          media: [],
          bytes: {},
        ),
        throwsStateError,
      );
    }
    await expectLater(
      posts.publish(
        spotId: 'melon',
        caption: '動画',
        category: 'グルメ',
        rating: 5,
        media: [const PostMedia(id: 'bad', source: '')],
        bytes: {'bad': testImageBytes.sublist(0, 8)},
      ),
      throwsStateError,
    );
    expect(images.calls, 0);
    expect(repository.value.posts, isEmpty);
  });
}
