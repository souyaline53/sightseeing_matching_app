import 'dart:convert';
import 'package:sightseeing_matching_app/repository/cloud_image_repository.dart';
import 'package:sightseeing_matching_app/service/post_media_picker.dart';
import 'package:sightseeing_matching_app/service/image_policy.dart';
import 'dart:async';
import 'package:sightseeing_matching_app/model/account_profile.dart';
import 'package:sightseeing_matching_app/repository/account_repository.dart';
import 'package:sightseeing_matching_app/repository/guest_identity_repository.dart';
import 'dart:typed_data';
import 'package:sightseeing_matching_app/model/post.dart';
import 'package:sightseeing_matching_app/repository/posts_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/travel_catalog.dart';
import 'catalog_fixtures.dart';
import 'package:sightseeing_matching_app/repository/settings_repository.dart';

class MemorySettingsStorage implements SettingsStorage {
  String? value;
  bool failRead = false, failWrite = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('read unavailable');
    return value;
  }

  @override
  Future<void> write(String value) async {
    if (failWrite) throw StateError('write unavailable');
    this.value = value;
  }
}

late TravelCatalog testCatalog;
List<Experience> get experiences => testCatalog.experiences;

void initializeCatalogTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    testCatalog = fixtureCatalog();
  });
}

PostsState fixturePosts() => PostsState(
  posts: [
    for (var i = 0; i < 3; i++)
      TravelPost(
        id: 'test-post-$i',
        userId: 'test-user-$i',
        userName: '検証ユーザー$i',
        spotId: ['melon', 'lake', 'otaru'][i],
        category: 'グルメ',
        caption: '検証用本文',
        media: [
          PostMedia(
            id: 'test-image-$i',
            source: 'https://example.test/image-$i.jpg',
          ),
        ],
        rating: 5,
        createdAt: DateTime.utc(2026, 1, 3 - i),
        comments: [
          PostComment(
            id: 'test-comment-$i',
            userId: 'visitor',
            userName: '検証',
            text: '検証コメント',
            createdAt: DateTime.utc(2026),
          ),
        ],
      ),
  ],
  followingIds: {'test-user-0'},
);

class MemoryPostsRepository implements PostsRepository {
  PostsState value;
  bool failRead = false, failWrite = false;
  final changes = StreamController<PostsState>.broadcast(sync: true);
  MemoryPostsRepository({PostsState? initial})
    : value = initial ?? PostsState();
  MemoryPostsRepository.seeded() : value = fixturePosts();
  @override
  Stream<PostsState> watch() async* {
    if (failRead) throw StateError('read unavailable');
    yield value;
    yield* changes.stream;
  }

  Future<void> update(PostsState next) async {
    if (failWrite) throw StateError('write unavailable');
    value = next;
    changes.add(value);
  }

  @override
  Future<void> create(TravelPost post) =>
      update(value.copyWith(posts: [post, ...value.posts]));
  @override
  Future<void> toggleLike(String id) {
    final liked = {...value.likedIds};
    final remove = liked.remove(id);
    if (!remove) liked.add(id);
    return update(
      value.copyWith(
        likedIds: liked,
        posts: [
          for (final p in value.posts)
            p.id == id
                ? p.copyWith(likeCount: p.likeCount + (remove ? -1 : 1))
                : p,
        ],
      ),
    );
  }

  @override
  Future<void> toggleSaved(String id) {
    final saved = {...value.savedIds};
    if (!saved.remove(id)) saved.add(id);
    return update(value.copyWith(savedIds: saved));
  }

  @override
  Future<void> toggleFollow(String id) {
    final follows = {...value.followingIds};
    if (!follows.remove(id)) follows.add(id);
    return update(value.copyWith(followingIds: follows));
  }

  @override
  Future<void> addComment(String id, PostComment comment) => update(
    value.copyWith(
      posts: [
        for (final p in value.posts)
          p.id == id ? p.copyWith(comments: [...p.comments, comment]) : p,
      ],
    ),
  );
  @override
  Future<void> delete(TravelPost post) => update(
    value.copyWith(posts: value.posts.where((p) => p.id != post.id).toList()),
  );
}

class MemoryGuestIdentityRepository implements GuestIdentityRepository {
  GuestIdentity value;
  MemoryGuestIdentityRepository([
    this.value = const GuestIdentity('local-user'),
  ]);
  @override
  Future<GuestIdentity> load() async => value;
}

class FakeAccountRepository implements AccountRepository {
  AccountIdentity identity;
  final Map<String, AccountDetails> profiles = {};
  final changes = StreamController<void>.broadcast();
  bool failSave = false;
  String? lastPassword;
  String? resetEmail;
  final String guestUid;
  FakeAccountRepository({
    AccountIdentity? identity,
    this.guestUid = 'local-user',
  }) : identity = identity ?? AccountIdentity(uid: guestUid);
  @override
  bool get available => true;
  @override
  String? get unavailableMessage => null;
  @override
  Stream<AccountIdentity> watchIdentity() async* {
    yield identity;
    yield* changes.stream.map((_) => identity);
  }

  @override
  Stream<AccountDetails?> watchProfile(String uid) async* {
    yield profiles[uid];
    yield* changes.stream.map((_) => profiles[uid]);
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required AccountDetails details,
  }) async {
    if (password.length < 6) throw const AccountFailure('パスワードは6文字以上にしてください。');
    if (failSave) throw const AccountFailure('保存できませんでした。');
    lastPassword = password;
    identity = AccountIdentity(
      uid: 'firebase-uid-test',
      email: email,
      registered: true,
      displayName: details.nickname,
    );
    profiles[identity.uid] = details;
    changes.add(null);
  }

  @override
  Future<void> signIn(String email, String password) async {
    if (password != 'abcdef') {
      throw const AccountFailure('メールアドレスまたはパスワードを確認してください。');
    }
    identity = AccountIdentity(
      uid: 'firebase-uid-test',
      email: email,
      registered: true,
      displayName: profiles['firebase-uid-test']?.nickname ?? 'プロフィール未登録',
    );
    changes.add(null);
  }

  @override
  Future<void> saveProfile(AccountDetails details) async {
    if (failSave) throw const AccountFailure('保存できませんでした。');
    profiles[identity.uid] = details;
    identity = AccountIdentity(
      uid: identity.uid,
      email: identity.email,
      registered: true,
      displayName: details.nickname,
    );
    changes.add(null);
  }

  @override
  Future<void> signOut() async {
    identity = AccountIdentity(uid: guestUid);
    changes.add(null);
  }

  @override
  Future<void> resetPassword(String email) async {
    resetEmail = email;
  }

  @override
  Future<void> sendVerification() async {}
  @override
  Future<void> reloadIdentity() async {}
}

Uint8List get testImageBytes => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class MemoryImagePicker implements PostMediaPicker {
  @override
  Future<List<PickedPostMedia>> pick(
    PostMediaSource source, {
    required int remaining,
  }) async => [
    PickedPostMedia(
      const PostMedia(
        id: 'picked-image',
        source: 'local://picked-image',
        mimeType: 'image/png',
      ),
      testImageBytes,
    ),
  ];
}

class MemoryCloudImages implements CloudImageRepository {
  final String owner;
  final files = <String, Uint8List>{};
  int calls = 0;
  int? failUploadAt;
  MemoryCloudImages({this.owner = 'local-user'});
  @override
  Future<String> postOwner() async => owner;
  @override
  Future<CloudImage> upload(String prefix, Uint8List bytes) async {
    final mime = await validateImage(bytes);
    calls++;
    if (calls == failUploadAt) throw StateError('アップロード失敗');
    final path = '$prefix.${imageExtension(mime)}';
    files[path] = bytes;
    return CloudImage('https://example.test/$path', path);
  }

  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }
}
