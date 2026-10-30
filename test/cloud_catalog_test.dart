import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/model/account_profile.dart';
import 'package:sightseeing_matching_app/model/catalog_record.dart';
import 'package:sightseeing_matching_app/model/post.dart';
import 'package:sightseeing_matching_app/repository/firestore_catalog_repository.dart';
import 'package:sightseeing_matching_app/repository/cloud_image_repository.dart';
import 'package:sightseeing_matching_app/service/cloud/cloud_services.dart';
import 'package:sightseeing_matching_app/service/cloud/catalog_admin_service.dart';
import 'package:sightseeing_matching_app/service/image_policy.dart';
import 'package:sightseeing_matching_app/state/posts_state.dart';
import 'package:sightseeing_matching_app/state/account_state.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot;

class _User extends Fake implements User {
  final bool verified;
  _User(this.verified);
  @override
  String get uid => 'admin-test';
  @override
  String? get email => adminEmail;
  @override
  bool get isAnonymous => false;
  @override
  bool get emailVerified => verified;
}

class _Auth extends Fake implements FirebaseAuth {
  @override
  final User? currentUser;
  _Auth(this.currentUser);
}

class _Firestore extends Fake implements FirebaseFirestore {}

class _Storage extends Fake implements FirebaseStorage {}

class _Catalog extends FirestoreCatalogRepository {
  final data = <String, CatalogRecord>{};
  _Catalog() : super(() => throw UnimplementedError());
  @override
  Future<List<CatalogRecord>> records(CatalogKind kind) async =>
      data.values.where((r) => r.kind == kind).toList();
  @override
  Future<void> save(
    CatalogKind kind,
    String id,
    Map<String, dynamic> values, {
    required bool creating,
  }) async {
    if (creating && data.containsKey(id)) throw StateError('IDが重複しています');
    data[id] = CatalogRecord(id, kind, values);
  }

  @override
  Future<void> delete(CatalogRecord record) async {
    data.remove(record.id);
  }
}

const spotValues = {
  'title': '新しい冒険',
  'area': '夕張',
  'category': '自然',
  'description': '紹介',
  'story': '物語',
  'surprise': '発見',
  'minutes': 60,
  'accessMinutes': 90,
  'order': 0,
};
final photoDraft = CatalogPhotoDraft(bytes: testImageBytes);
Future<void> revealEditor(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final scroll = find
      .descendant(
        of: find.byKey(const ValueKey('catalog-edit-form')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(finder, 220, scrollable: scroll);
  await Scrollable.ensureVisible(tester.element(finder), alignment: .2);
  await tester.pumpAndSettle();
}

void main() {
  initializeCatalogTests();
  test(
    'image policy rejects empty, damaged, video and exactly 5MB; valid image below limit passes',
    () async {
      expect(await validateImage(testImageBytes), 'image/png');
      final under = Uint8List(maxImageBytes - 1)..setAll(0, testImageBytes);
      expect(await validateImage(under), 'image/png');
      for (final bytes in [
        Uint8List(0),
        Uint8List(maxImageBytes),
        Uint8List.fromList([0, 0, 0, 24, 102, 116, 121, 112]),
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ]) {
        await expectLater(validateImage(bytes), throwsStateError);
      }
    },
  );
  test(
    'catalog field validation rejects bad IDs, negative times and invalid transit',
    () {
      expect(
        validateCatalogRecord(CatalogKind.sightseeing, 'new-spot', spotValues),
        isNull,
      );
      expect(
        validateCatalogRecord(CatalogKind.sightseeing, '../bad', spotValues),
        isNotNull,
      );
      expect(
        validateCatalogRecord(CatalogKind.sightseeing, 'new', {
          ...spotValues,
          'minutes': -1,
        }),
        isNotNull,
      );
      expect(
        validateCatalogRecord(CatalogKind.transit, 'new', spotValues),
        isNotNull,
      );
      expect(
        isAdminIdentity(
          const AccountIdentity(uid: 'x', email: adminEmail, registered: true),
        ),
        isTrue,
      );
      expect(
        isAdminIdentity(
          const AccountIdentity(
            uid: 'x',
            email: 'other@example.com',
            registered: true,
          ),
        ),
        isFalse,
      );
    },
  );
  test(
    'failed image upload and failed Firestore create roll back images without losing existing posts',
    () async {
      final images = MemoryCloudImages()..failUploadAt = 2;
      final local = MemoryPostsRepository();
      final container = ProviderContainer(
        overrides: [
          catalogProvider.overrideWith((ref) => Stream.value(testCatalog)),
          cloudImageRepositoryProvider.overrideWithValue(images),
          postsRepositoryProvider.overrideWithValue(local),
          guestIdentityRepositoryProvider.overrideWithValue(
            MemoryGuestIdentityRepository(),
          ),
          accountRepositoryProvider.overrideWith(
            (ref) => FakeAccountRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(postsProvider, (_, _) {});
      container.listen(catalogProvider, (_, _) {});
      final initial = await container.read(postsProvider.future);
      final posts = container.read(postsProvider.notifier);
      Future<void> publish() => posts.publish(
        spotId: 'melon',
        caption: '写真',
        category: 'グルメ',
        rating: 5,
        media: [
          const PostMedia(id: 'a', source: ''),
          const PostMedia(id: 'b', source: ''),
        ],
        bytes: {'a': testImageBytes, 'b': testImageBytes},
      );
      await expectLater(publish(), throwsStateError);
      expect(images.files, isEmpty);
      expect(container.read(postsProvider).requireValue.posts, initial.posts);
      images.failUploadAt = null;
      local.failWrite = true;
      await expectLater(publish(), throwsStateError);
      expect(images.files, isEmpty);
      expect(container.read(postsProvider).requireValue.posts, initial.posts);
    },
  );
  testWidgets(
    'admin menu can edit and delete; transit tab and all fields remain accessible',
    (tester) async {
      final repository = _Catalog()
        ..data['test-spot'] =
            CatalogRecord('test-spot', CatalogKind.sightseeing, {
              ...spotValues,
              'photo': '',
              'photoPath': '',
              'additionalPhotos': [],
              'additionalPhotoPaths': [],
            });
      final account = FakeAccountRepository(
        identity: const AccountIdentity(
          uid: 'admin-test',
          email: adminEmail,
          registered: true,
          emailVerified: true,
        ),
      );
      await boot(
        tester,
        accountRepository: account,
        adminRepository: repository,
        cloudServices: CloudServices(
          _Firestore(),
          _Storage(),
          _Auth(_User(true)),
        ),
      );
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('admin-menu'));
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('観光地情報'), findsOneWidget);
      expect(find.text('交通情報'), findsOneWidget);
      await tester.tap(find.text('新しい冒険'));
      await tester.pumpAndSettle();
      final title = find.byKey(const ValueKey('catalog-title'));
      await revealEditor(tester, title);
      await tester.enterText(title, '変更した冒険');
      final save = find.byKey(const ValueKey('catalog-save'));
      await revealEditor(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repository.data['test-spot']!.title, '変更した冒険');
      await tester.tap(find.byTooltip('削除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '削除'));
      await tester.pumpAndSettle();
      expect(repository.data, isEmpty);
      await tester.tap(find.text('交通情報'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('追加'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('catalog-id')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'catalog failure still allows guest profile access and hides admin menu',
    (tester) async {
      await boot(tester, catalogFailure: StateError('offline'));
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      expect(find.text('ゲストさん'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-menu')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
