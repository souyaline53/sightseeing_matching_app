@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_web/firebase_storage_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;
import 'package:sightseeing_matching_app/firebase_options.dart';
import 'package:sightseeing_matching_app/model/account_profile.dart';
import 'package:sightseeing_matching_app/repository/firebase_account_repository.dart';
import 'package:sightseeing_matching_app/repository/firestore_chat_repository.dart';
import 'package:sightseeing_matching_app/service/auth/firebase_runtime.dart';
import 'package:sightseeing_matching_app/service/cloud/cloud_services.dart';

const _base =
    'http://127.0.0.1:8080/v1/projects/sightseeing-matching-prototype/databases/(default)/documents/';

// テスト用の役割変更・終了時の清掃だけに使うエミュレーター管理API。
Future<void> fixtureRequest(String path, String method, [Object? body]) async {
  final response = await web.window
      .fetch(
        '$_base$path'.toJS,
        web.RequestInit(
          method: method,
          headers: web.Headers()
            ..set('Authorization', 'Bearer owner')
            ..set('Content-Type', 'application/json'),
          body: body == null ? null : jsonEncode(body).toJS,
        ),
      )
      .toDart;
  expect(response.status, anyOf(200, 404));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'two actual Flutter Web clients reuse a room and receive cloud messages; profile edits preserve municipal role',
    () async {
      expect(
        const String.fromEnvironment('FIREBASE_EMULATOR_HOST'),
        '127.0.0.1',
      );
      FirebaseCoreWeb.registerWith(webPluginRegistrar);
      FirebaseAuthWeb.registerWith(webPluginRegistrar);
      FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
      FirebaseStorageWeb.registerWith(webPluginRegistrar);
      expect((await initializeAccountFirebase()).available, isTrue);
      final auth = FirebaseAuth.instance;
      await auth.signOut();
      final db = FirebaseFirestore.instance;
      final storage = FirebaseStorage.instance;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final a = (await auth.createUserWithEmailAndPassword(
        email: 'chat-a-$stamp@example.test',
        password: 'abcdef',
      )).user!;
      final app = await Firebase.initializeApp(
        name: 'chat-peer-$stamp',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final peerAuth = FirebaseAuth.instanceFor(app: app);
      await peerAuth.useAuthEmulator('127.0.0.1', 9099);
      final peerDb = FirebaseFirestore.instanceFor(app: app)
        ..useFirestoreEmulator('127.0.0.1', 8080);
      final peerStorage = FirebaseStorage.instanceFor(app: app);
      await peerStorage.useStorageEmulator('127.0.0.1', 9199);
      final b = (await peerAuth.createUserWithEmailAndPassword(
        email: 'chat-b-$stamp@example.test',
        password: 'abcdef',
      )).user!;
      final aProfile = FirebaseAccountRepository(
        auth: auth,
        firestore: db,
        guest: const GuestIdentity('guest'),
      );
      final bProfile = FirebaseAccountRepository(
        auth: peerAuth,
        firestore: peerDb,
        guest: const GuestIdentity('guest'),
      );
      const detailsA = AccountDetails(
        nickname: '旅の仲間',
        ageGroup: '30代',
        prefecture: '北海道',
        municipality: '札幌市',
      );
      const detailsB = AccountDetails(
        nickname: '観光案内',
        ageGroup: '30代',
        prefecture: '北海道',
        municipality: '札幌市',
      );
      final alice = FirestoreChatRepository(CloudServices(db, storage, auth));
      final bob = FirestoreChatRepository(
        CloudServices(peerDb, peerStorage, peerAuth),
      );
      String? roomId;
      try {
        await aProfile.saveProfile(detailsA);
        await bProfile.saveProfile(detailsB);
        final people = await alice.watchAccounts().first;
        expect(people.any((person) => person.uid == b.uid), isTrue);
        final ids = await Future.wait([
          alice.openRoom(b.uid),
          bob.openRoom(a.uid),
        ]);
        expect(ids[0], ids[1]);
        roomId = ids.first;
        expect((await alice.watchRooms(a.uid).first).single.id, roomId);
        final incoming = bob
            .watchMessages(roomId)
            .firstWhere((items) => items.any((m) => m.text == '行き方を教えてください'));
        await alice.send(roomId, '行き方を教えてください');
        expect((await incoming).single.senderId, a.uid);
        final preview = alice
            .watchRooms(a.uid)
            .firstWhere((rooms) => rooms.single.lastMessage == 'バスで行けます');
        await bob.send(roomId, 'バスで行けます');
        expect((await preview).single.lastSenderId, b.uid);
        final restored = FirestoreChatRepository(
          CloudServices(db, storage, auth),
        );
        final history = await restored
            .watchMessages(roomId)
            .firstWhere((items) => items.length == 2);
        expect(history.map((message) => message.text), [
          'バスで行けます',
          '行き方を教えてください',
        ]);
        expect(await restored.openRoom(b.uid), roomId);
        await expectLater(alice.send(roomId, ' '), throwsStateError);
        await expectLater(alice.send(roomId, 'x' * 2001), throwsStateError);
        await fixtureRequest(
          'users/${b.uid}?updateMask.fieldPaths=userType',
          'PATCH',
          {
            'fields': {
              'userType': {'stringValue': 'municipality'},
            },
          },
        );
        await bProfile.saveProfile(
          const AccountDetails(
            nickname: '更新後の観光案内',
            ageGroup: '40代',
            prefecture: '北海道',
            municipality: '札幌市',
          ),
        );
        final profile = await bProfile.watchProfile(b.uid).first;
        expect(profile!.userType, UserType.municipality);
        final updated = (await alice.watchAccounts().firstWhere(
          (people) => people.any(
            (person) => person.uid == b.uid && person.displayName == '更新後の観光案内',
          ),
        )).singleWhere((person) => person.uid == b.uid);
        expect(updated.userType, UserType.municipality);
        expect(
          (await db.collection('users').doc(a.uid).get()).data()!['userType'],
          'general',
        );
      } finally {
        if (roomId != null) {
          final messages = await db
              .collection('chat_rooms')
              .doc(roomId)
              .collection('messages')
              .get();
          for (final message in messages.docs) {
            await fixtureRequest(
              'chat_rooms/$roomId/messages/${message.id}',
              'DELETE',
            );
          }
          await fixtureRequest('chat_rooms/$roomId', 'DELETE');
        }
        for (final uid in [a.uid, b.uid]) {
          await fixtureRequest('public_profiles/$uid', 'DELETE');
          await fixtureRequest('users/$uid', 'DELETE');
        }
        await a.delete();
        await b.delete();
        await auth.signOut();
        await peerAuth.signOut();
        await app.delete();
      }
    },
    skip: !const bool.fromEnvironment('AUTH_EMULATORS_TEST'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
