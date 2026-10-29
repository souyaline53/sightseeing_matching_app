import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/post.dart';
import 'package:sightseeing_matching_app/repository/posts_repository.dart';
import 'post_test_database_stub.dart'
    if (dart.library.js_interop) 'post_test_database_web.dart';

void main() {
  test(
    'browser posts, media and reactions survive closing and reopening IndexedDB',
    () async {
      final name =
          'tabisaki-post-test-${DateTime.now().microsecondsSinceEpoch}';
      final first = LocalPostsRepository(
        open: () => openTestPostsDatabase(name),
      );
      addTearDown(() => deleteTestPostsDatabase(name));
      final media = Uint8List.fromList([0, 255, 4, 12, 80]);
      final post = TravelPost(
        id: 'web-post',
        userId: localPostUserId,
        userName: 'あなた',
        spotId: 'melon',
        category: 'グルメ',
        caption: 'Webの投稿',
        rating: 5,
        createdAt: DateTime(2030),
        media: [const PostMedia(id: 'web-media', source: 'local://web-media')],
      );
      await first.save(
        PostsState(
          posts: [post],
          likedIds: {post.id},
          savedIds: {post.id},
          followingIds: {'sample-user-0'},
        ),
        media: {'web-media': media},
      );
      await first.close();
      final second = LocalPostsRepository(
        open: () => openTestPostsDatabase(name),
      );
      final restored = (await second.load())!;
      expect(restored.posts.single.spotId, 'melon');
      expect(restored.likedIds, contains(post.id));
      expect(restored.savedIds, contains(post.id));
      expect(await second.readMedia('web-media'), media);
      await second.close();
    },
    skip: !kIsWeb,
  );
}
