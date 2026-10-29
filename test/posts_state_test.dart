import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sightseeing_matching_app/data/mock_data.dart';
import 'package:sightseeing_matching_app/model/post.dart';
import 'package:sightseeing_matching_app/repository/posts_repository.dart';
import 'package:sightseeing_matching_app/state/posts_state.dart';
import 'test_support.dart';
import 'package:sightseeing_matching_app/state/account_state.dart';

void main() {
  initializeMockCatalogTests();
  ProviderContainer open(PostsRepository repository) => ProviderContainer(
    overrides: [
      guestIdentityRepositoryProvider.overrideWithValue(
        MemoryGuestIdentityRepository(),
      ),
      accountRepositoryProvider.overrideWith((ref) => FakeAccountRepository()),
      mockCatalogProvider.overrideWith((ref) => testCatalog),
      postsRepositoryProvider.overrideWithValue(repository),
    ],
  );
  test('local media and post data survive a new repository instance', () async {
    final name = newPostId('database-test');
    final factory = databaseFactoryMemory;
    addTearDown(() => factory.deleteDatabase(name));
    final first = LocalPostsRepository(open: () => factory.openDatabase(name));
    final bytes = Uint8List.fromList([0, 1, 2, 3, 255]);
    final media = PostMedia(id: 'image', source: 'local://image');
    final post = TravelPost(
      id: 'p',
      userId: localPostUserId,
      userName: 'あなた',
      spotId: 'melon',
      category: 'グルメ',
      caption: 'また行きたい #夕張',
      media: [media],
      rating: 5,
      createdAt: DateTime(2030),
      likeCount: 2,
      comments: [
        PostComment(
          id: 'c',
          userId: localPostUserId,
          userName: 'あなた',
          text: 'いい景色',
          createdAt: DateTime(2030),
        ),
      ],
    );
    final state = PostsState(
      posts: [post],
      likedIds: {'p'},
      savedIds: {'p'},
      followingIds: {'sample-user-0'},
    );
    await first.save(state, media: {'image': bytes});
    await first.close();
    final second = LocalPostsRepository(open: () => factory.openDatabase(name));
    addTearDown(second.close);
    final restored = (await second.load())!;
    expect(restored.toJson(), state.toJson());
    expect(restored.posts.single.createdAt.isUtc, isTrue);
    expect(await second.readMedia('image'), bytes);
    await second.save(PostsState(), removeMedia: {'image'});
    expect((await second.load())!.posts, isEmpty);
    expect(await second.readMedia('image'), isNull);
  });
  test(
    'publish, like, comment, follow and bookmark persist and remain independent',
    () async {
      final repository = MemoryPostsRepository();
      final container = open(repository);
      addTearDown(container.dispose);
      final seeded = await container.read(postsProvider.future);
      final post = seeded.posts.first;
      final controller = container.read(postsProvider.notifier);
      await controller.toggleLike(post.id);
      await controller.toggleSaved(post.id);
      await controller.comment(post.id, '  次の週末に行ってみたい！  ');
      await controller.toggleFollow(post.userId);
      final data = container.read(postsProvider).requireValue;
      expect(data.posts.first.likeCount, post.likeCount + 1);
      expect(data.posts.first.commentCount, post.commentCount + 1);
      expect(data.posts.first.comments.last.text, '次の週末に行ってみたい！');
      expect(data.savedIds, contains(post.id));
      expect(data.followingIds, isNot(contains(post.userId)));
      final reopened = open(repository);
      addTearDown(reopened.dispose);
      expect(
        (await reopened.read(postsProvider.future)).toJson(),
        data.toJson(),
      );
      final bytes = Uint8List.fromList([0, 1, 2]);
      await controller.publish(
        spotId: 'melon',
        caption: '自分の発見 #夕張',
        category: 'グルメ',
        rating: 4,
        media: [const PostMedia(id: 'own-image', source: 'local://own-image')],
        bytes: {'own-image': bytes},
      );
      final own = container.read(postsProvider).requireValue.posts.first;
      expect(own.userId, localPostUserId);
      expect(own.spotId, 'melon');
      expect(repository.media['own-image'], bytes);
      await expectLater(controller.delete(post.id), throwsStateError);
      await controller.delete(own.id);
      expect(
        container
            .read(postsProvider)
            .requireValue
            .posts
            .any((p) => p.id == own.id),
        isFalse,
      );
      expect(repository.media.containsKey('own-image'), isFalse);
      expect(
        container.read(postsProvider).requireValue.posts.first.commentCount,
        data.posts.first.commentCount,
      );
    },
  );
  test(
    'failed save retains state and the next operation can be retried',
    () async {
      final repository = MemoryPostsRepository();
      final container = open(repository);
      addTearDown(container.dispose);
      final initial = await container.read(postsProvider.future);
      final controller = container.read(postsProvider.notifier);
      repository.failWrite = true;
      await expectLater(
        controller.toggleLike(initial.posts.first.id),
        throwsStateError,
      );
      expect(
        container.read(postsProvider).requireValue.toJson(),
        initial.toJson(),
      );
      repository.failWrite = false;
      await Future.wait([
        controller.toggleLike(initial.posts.first.id),
        controller.toggleLike(initial.posts.first.id),
      ]);
      expect(
        container.read(postsProvider).requireValue.toJson(),
        initial.toJson(),
      );
    },
  );
  test(
    'invalid posts are rejected without changing the catalog or saved posts',
    () async {
      final repository = MemoryPostsRepository();
      final container = open(repository);
      addTearDown(container.dispose);
      final original = await container.read(postsProvider.future);
      final controller = container.read(postsProvider.notifier);
      for (final spotId in ['unknown', 'melon']) {
        await expectLater(
          controller.publish(
            spotId: spotId,
            caption: ' ',
            category: '自然',
            rating: 5,
            media: [],
          ),
          throwsStateError,
        );
      }
      await expectLater(
        controller.publish(
          spotId: 'melon',
          caption: '発見',
          category: '自然',
          rating: double.nan,
          media: [PostMedia(id: 'x', source: experiences.first.photo)],
        ),
        throwsStateError,
      );
      await expectLater(
        controller.publish(
          spotId: 'melon',
          caption: '発見',
          category: '自然',
          rating: 4,
          media: [const PostMedia(id: 'missing', source: 'local://missing')],
        ),
        throwsStateError,
      );
      expect(
        container.read(postsProvider).requireValue.toJson(),
        original.toJson(),
      );
      final roundTrip = PostsState.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(roundTrip.toJson(), original.toJson());
      expect(() => roundTrip.posts.clear(), throwsUnsupportedError);
    },
  );
}
