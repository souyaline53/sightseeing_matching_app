@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_web/firebase_storage_web.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:web/web.dart' as web;
import 'package:sightseeing_matching_app/firebase_options.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'package:sightseeing_matching_app/model/catalog_record.dart';
import 'package:sightseeing_matching_app/model/post.dart';
import 'package:sightseeing_matching_app/repository/firestore_posts_repository.dart';
import 'package:sightseeing_matching_app/service/auth/firebase_runtime.dart';
import 'package:sightseeing_matching_app/service/cloud/catalog_admin_service.dart';
import 'package:sightseeing_matching_app/service/cloud/cloud_services.dart';
import 'package:sightseeing_matching_app/service/cloud/image_optimization_service.dart';
import 'package:sightseeing_matching_app/service/display_image.dart';
import 'package:sightseeing_matching_app/state/account_state.dart';
import 'package:sightseeing_matching_app/state/posts_state.dart';
import 'test_support.dart';
import 'web_preferences.dart';

Future<void> absentImage(String path) async {
  final response = await web.window
      .fetch(
        'http://127.0.0.1:9199/v0/b/sightseeing-matching-prototype.firebasestorage.app/o/${Uri.encodeComponent(path)}'
            .toJS,
        web.RequestInit(
          headers: web.Headers()..set('Authorization', 'Bearer owner'),
        ),
      )
      .toDart;
  expect(response.status, 404);
}

// 既存の大きな画像を模擬するため、エミュレーターの管理APIだけで配置する。
Future<void> seedLegacyImage(Reference ref, Uint8List bytes) async {
  final response = await web.window
      .fetch(
        'http://127.0.0.1:9199/v0/b/${ref.bucket}/o?uploadType=media&name=${Uri.encodeComponent(ref.fullPath)}'
            .toJS,
        web.RequestInit(
          method: 'POST',
          headers: web.Headers()
            ..set('Authorization', 'Bearer owner')
            ..set('Content-Type', 'image/png')
            ..set('X-Goog-Upload-Protocol', 'raw'),
          body: bytes.toJS,
        ),
      )
      .toDart;
  expect(response.status, 200);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real clients share cloud posts, reactions and comments; personal data and author writes are isolated',
    () async {
      expect(
        const String.fromEnvironment('FIREBASE_EMULATOR_HOST'),
        '127.0.0.1',
      );
      FirebaseCoreWeb.registerWith(webPluginRegistrar);
      FirebaseAuthWeb.registerWith(webPluginRegistrar);
      FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
      FirebaseStorageWeb.registerWith(webPluginRegistrar);
      registerPreferencesForTest();
      final runtime = await initializeAccountFirebase();
      expect(runtime.available, isTrue);
      final auth = FirebaseAuth.instance;
      await auth.signOut();
      final admin = (await auth.createUserWithEmailAndPassword(
        email: adminEmail,
        password: 'abcdef',
      )).user!;
      final response = await web.window
          .fetch(
            'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:update?key=local-only'
                .toJS,
            web.RequestInit(
              method: 'POST',
              headers: web.Headers()
                ..set('Content-Type', 'application/json')
                ..set('Authorization', 'Bearer owner'),
              body: jsonEncode({
                'localId': admin.uid,
                'emailVerified': true,
              }).toJS,
            ),
          )
          .toDart;
      expect(response.status, 200);
      await admin.reload();
      await auth.currentUser!.getIdToken(true);
      await auth.currentUser!.updateDisplayName('投稿者');
      final container = ProviderContainer(
        overrides: [
          firebaseRuntimeProvider.overrideWith((ref) => runtime),
          guestIdentityRepositoryProvider.overrideWithValue(
            MemoryGuestIdentityRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(currentAccountProvider, (_, _) {});
      container.listen(postsProvider, (_, _) {});
      container.listen(catalogProvider, (_, _) {});
      await container.read(accountIdentityProvider.future);
      final service = container.read(catalogAdminServiceProvider);
      final catalog = container.read(adminCatalogRepositoryProvider);
      final id = 'browser-${DateTime.now().microsecondsSinceEpoch}';
      final values = {
        'title': 'クラウドの体験',
        'area': '北海道',
        'category': '自然',
        'description': '紹介',
        'story': '物語',
        'surprise': '発見',
        'minutes': 60,
        'accessMinutes': 90,
        'order': 0,
      };
      final observerApp = await Firebase.initializeApp(
        name: 'observer',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final observerAuth = FirebaseAuth.instanceFor(app: observerApp);
      await observerAuth.useAuthEmulator('127.0.0.1', 9099);
      final observerDb = FirebaseFirestore.instanceFor(app: observerApp)
        ..useFirestoreEmulator('127.0.0.1', 8080);
      final observerStorage = FirebaseStorage.instanceFor(app: observerApp);
      await observerStorage.useStorageEmulator('127.0.0.1', 9199);
      final guest = (await observerAuth.signInAnonymously()).user!;
      final observer = FirestorePostsRepository(
        () async => CloudServices(observerDb, observerStorage, observerAuth),
      );
      final writer = container.read(postsRepositoryProvider);
      TravelPost? posted;
      final rawFiles = <Reference>[];
      try {
        await service.save(CatalogKind.sightseeing, id, values, [
          CatalogPhotoDraft(bytes: testImageBytes),
        ]);
        var record = (await catalog.records(
          CatalogKind.sightseeing,
        )).singleWhere((r) => r.id == id);
        final oldPath = record.photos.single.path;
        await service.save(
          CatalogKind.sightseeing,
          id,
          {...values, 'title': '編集した体験'},
          [CatalogPhotoDraft(bytes: testImageBytes)],
          original: record,
        );
        await absentImage(oldPath);
        expect(
          (await container.read(postsProvider.future)).posts,
          isEmpty,
          reason: '投稿の自動生成はしない',
        );
        final largeImage = Uint8List(4999999)..setAll(0, testImageBytes);
        await container
            .read(postsProvider.notifier)
            .publish(
              spotId: id,
              caption: '実際に入力した本文 #旅',
              category: '自然',
              rating: 4,
              media: [const PostMedia(id: 'image', source: '')],
              bytes: {'image': largeImage},
            );
        posted = (await observer.watch().firstWhere(
          (s) => s.posts.any((p) => p.spotId == id),
        )).posts.singleWhere((p) => p.spotId == id);
        expect(posted.caption, '実際に入力した本文 #旅');
        expect(posted.rating, 4);
        expect(posted.userId, admin.uid);
        expect(posted.userName, '投稿者');
        expect(
          (await FirebaseStorage.instance
                  .ref(posted.media.single.storagePath)
                  .getMetadata())
              .size,
          lessThanOrEqualTo(maxDisplayImageBytes),
        );
        final imageMetadata = await FirebaseStorage.instance
            .ref(posted.media.single.storagePath)
            .getMetadata();
        expect(imageMetadata.contentType, 'image/jpeg');
        expect(imageMetadata.cacheControl, displayImageCacheControl);
        await observer.toggleLike(posted.id);
        await observer.toggleSaved(posted.id);
        await observer.toggleFollow(admin.uid);
        await observer.addComment(
          posted.id,
          PostComment(
            id: newPostId('comment'),
            userId: guest.uid,
            userName: 'ゲストさん',
            text: '別の利用者のコメント',
            createdAt: DateTime.now(),
          ),
        );
        final shared = await observer.watch().firstWhere(
          (s) =>
              s.posts.any(
                (p) =>
                    p.id == posted!.id &&
                    p.commentCount == 1 &&
                    p.likeCount == 1,
              ) &&
              s.savedIds.contains(posted!.id) &&
              s.followingIds.contains(admin.uid) &&
              s.likedIds.contains(posted.id),
        );
        expect(shared.posts.single.likeCount, 1);
        expect(shared.likedIds, contains(posted.id));
        expect(shared.followingIds, contains(admin.uid));
        final own = await writer.watch().firstWhere(
          (s) => s.posts.any((p) => p.commentCount == 1),
        );
        expect(own.posts.single.comments.single.text, '別の利用者のコメント');
        expect(own.savedIds, isEmpty);
        expect(own.followingIds, isEmpty);
        expect(own.likedIds, isEmpty);
        await expectLater(observer.delete(posted), throwsStateError);
        await expectLater(
          observerDb.collection('posts').doc(posted.id).update({
            'caption': '改ざん',
          }),
          throwsA(isA<FirebaseException>()),
        );
        await expectLater(
          observerDb
              .collection('users')
              .doc(admin.uid)
              .collection('post_bookmarks')
              .get(),
          throwsA(isA<FirebaseException>()),
        );
        final reopened = FirestorePostsRepository(
          () async => CloudServices(observerDb, observerStorage, observerAuth),
        );
        expect(
          (await reopened.watch().firstWhere(
            (s) => s.savedIds.contains(posted!.id),
          )).posts.single.caption,
          posted.caption,
        );
        final imagePath = posted.media.single.storagePath;
        await container.read(postsProvider.notifier).delete(posted.id);
        await observer.watch().firstWhere((s) => s.posts.isEmpty);
        await absentImage(imagePath);
        expect(
          (await observerDb
                  .collection('post_comments')
                  .where('postId', isEqualTo: posted.id)
                  .get())
              .docs,
          isEmpty,
        );
        expect(
          (await observerDb
                  .collection('post_likes')
                  .where('postId', isEqualTo: posted.id)
                  .get())
              .docs,
          isEmpty,
        );
        await observer.toggleSaved(posted.id); // 削除済み投稿の保存も解除できる。
        await observer.toggleFollow(admin.uid);
        // 他ユーザーの既存の大きな画像も、管理者が表示用URLだけを置換できる。
        final legacyId = newPostId('legacy');
        final legacyFile = observerStorage.ref(
          'posts/${guest.uid}/$legacyId/original.png',
        );
        final catalogFile = FirebaseStorage.instance.ref(
          'catalog/sightseeing_spot/$id/original.png',
        );
        rawFiles.addAll([legacyFile, catalogFile]);
        await seedLegacyImage(legacyFile, largeImage);
        await seedLegacyImage(catalogFile, largeImage);
        await observer.create(
          TravelPost(
            id: legacyId,
            userId: guest.uid,
            userName: 'ゲストさん',
            spotId: id,
            category: '自然',
            caption: '既存の投稿本文',
            rating: 5,
            createdAt: DateTime.now(),
            media: [
              PostMedia(
                id: 'legacy-image',
                source: await legacyFile.getDownloadURL(),
                storagePath: legacyFile.fullPath,
                mimeType: 'image/png',
              ),
            ],
          ),
        );
        final latest = (await catalog.records(
          CatalogKind.sightseeing,
        )).singleWhere((r) => r.id == id);
        await catalog.save(CatalogKind.sightseeing, id, {
          ...latest.data,
          'photo': await catalogFile.getDownloadURL(),
          'photoPath': catalogFile.fullPath,
        }, creating: false);
        final optimized = await container
            .read(imageOptimizationServiceProvider)
            .run((_) {});
        expect(optimized.failures, isEmpty);
        expect(optimized.optimized, 2);
        final migrated = (await observer.watch().firstWhere(
          (s) => s.posts.any(
            (p) =>
                p.id == legacyId &&
                p.media.single.storagePath != legacyFile.fullPath,
          ),
        )).posts.singleWhere((p) => p.id == legacyId);
        expect(migrated.caption, '既存の投稿本文');
        expect(
          (await observerStorage
                  .ref(migrated.media.single.storagePath)
                  .getMetadata())
              .size,
          lessThanOrEqualTo(maxDisplayImageBytes),
        );
        expect(
          (await container.read(imageOptimizationServiceProvider).run((_) {}))
              .optimized,
          0,
        );
        await observer.delete(migrated);
        await observerStorage.ref(migrated.media.single.storagePath).delete();
        for (final file in rawFiles) {
          await file.delete();
        }
        rawFiles.clear();
        await observerAuth.signOut();
        expect((await observer.watch().first).savedIds, isEmpty);
      } finally {
        for (final file in rawFiles) {
          try {
            await file.delete();
          } catch (_) {}
        }
        // テストが途中失敗した場合も、このテストのデータだけを削除する。
        if (posted != null &&
            (await FirebaseFirestore.instance
                    .collection('posts')
                    .doc(posted.id)
                    .get())
                .exists) {
          await writer.delete(posted);
        }
        for (final record in await catalog.records(CatalogKind.sightseeing)) {
          if (record.id == id) await service.delete(record);
        }
        // 匿名アカウントはサインアウト前のUserから削除する。
        try {
          await guest.delete();
        } catch (_) {}
        await auth.currentUser!.delete();
        await auth.signOut();
        await observerApp.delete();
      }
    },
    skip: !const bool.fromEnvironment('AUTH_EMULATORS_TEST'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
