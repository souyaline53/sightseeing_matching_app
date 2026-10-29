import 'dart:async';
import 'package:sightseeing_matching_app/model/account_profile.dart';
import 'package:sightseeing_matching_app/repository/account_repository.dart';
import 'package:sightseeing_matching_app/repository/guest_identity_repository.dart';
import 'dart:typed_data';
import 'package:sightseeing_matching_app/model/post.dart';
import 'package:sightseeing_matching_app/repository/posts_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/mock_catalog.dart';
import 'package:sightseeing_matching_app/repository/mock_catalog_repository.dart';
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

late MockCatalog testCatalog;
List<Experience> get experiences => testCatalog.experiences;

void initializeMockCatalogTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    testCatalog = await MarkdownMockCatalogRepository().load();
  });
}

class MemoryPostsRepository implements PostsRepository {
  PostsState? value;
  final Map<String, Uint8List> media = {};
  bool failRead = false, failWrite = false;
  @override
  Future<PostsState?> load() async {
    if (failRead) throw StateError('read unavailable');
    return value == null ? null : PostsState.fromJson(value!.toJson());
  }

  @override
  Future<void> save(
    PostsState state, {
    Map<String, Uint8List> media = const {},
    Set<String> removeMedia = const {},
  }) async {
    if (failWrite) throw StateError('write unavailable');
    value = PostsState.fromJson(state.toJson());
    this.media.addAll({
      for (final entry in media.entries)
        entry.key: Uint8List.fromList(entry.value),
    });
    for (final id in removeMedia) {
      this.media.remove(id);
    }
  }

  @override
  Future<Uint8List?> readMedia(String id) async => media[id];
  @override
  Future<void> close() async {}
}

class MemoryGuestIdentityRepository implements GuestIdentityRepository {
  GuestIdentity value;
  MemoryGuestIdentityRepository([
    this.value = const GuestIdentity('local-user'),
  ]);
  @override
  Future<GuestIdentity> load() async => value;
  @override
  Future<void> claim(String uid) async {
    value = GuestIdentity(value.id, claimedByUid: value.claimedByUid ?? uid);
  }
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
