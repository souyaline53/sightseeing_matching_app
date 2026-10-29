@TestOn('browser')
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/model/account_profile.dart';
import 'package:sightseeing_matching_app/repository/guest_identity_repository.dart';
import 'package:sightseeing_matching_app/service/auth/firebase_runtime.dart';
import 'package:sightseeing_matching_app/state/account_state.dart';
import 'web_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real FlutterFire Web SDK registers, edits and restores profile with stable UID',
    () async {
      FirebaseCoreWeb.registerWith(webPluginRegistrar);
      FirebaseAuthWeb.registerWith(webPluginRegistrar);
      FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
      registerPreferencesForTest();
      expect(
        const String.fromEnvironment('FIREBASE_EMULATOR_HOST'),
        '127.0.0.1',
      );
      final runtime = await initializeAccountFirebase();
      expect(runtime.available, isTrue, reason: runtime.message);
      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;
      await auth.signOut();
      final guestRepository = LocalGuestIdentityRepository();
      final guest = await guestRepository.load();
      expect((await LocalGuestIdentityRepository().load()).id, guest.id);
      final container = ProviderContainer(
        overrides: [firebaseRuntimeProvider.overrideWith((ref) => runtime)],
      );
      addTearDown(container.dispose);
      container.listen(currentAccountProvider, (_, _) {});
      final identity = await container.read(accountIdentityProvider.future);
      expect(identity.uid, guest.id);
      expect(container.read(currentAccountProvider).name, 'ゲストさん');
      final email =
          'flutter-${DateTime.now().microsecondsSinceEpoch}@example.test';
      const details = AccountDetails(
        nickname: 'ブラウザの旅人',
        ageGroup: '20代',
        prefecture: '北海道',
        municipality: '札幌市',
      );
      final actions = container.read(accountActionsProvider);
      String? uid;
      try {
        await actions.register(
          email: email,
          password: 'abcdef',
          details: details,
        );
        uid = auth.currentUser!.uid;
        final repository = await container.read(
          accountRepositoryProvider.future,
        );
        expect(
          (await repository.watchProfile(uid).first)!.toMap(),
          details.toMap(),
        );
        expect(auth.currentUser!.displayName, details.nickname);
        expect((await guestRepository.load()).claimedByUid, uid);
        const edited = AccountDetails(
          nickname: '旅のつづき',
          ageGroup: '30代',
          prefecture: '東京都',
          municipality: '新宿区',
        );
        await actions.saveProfile(edited);
        final before = await firestore.collection('users').doc(uid).get();
        await actions.signOut();
        expect((await repository.watchIdentity().first).registered, isFalse);
        await actions.signIn(email, 'abcdef');
        expect(auth.currentUser!.uid, uid);
        expect(
          (await repository.watchProfile(uid).first)!.toMap(),
          edited.toMap(),
        );
        final after = await firestore.collection('users').doc(uid).get();
        expect(after.data()!['createdAt'], before.data()!['createdAt']);
        expect(after.data()!.containsKey('password'), isFalse);
      } finally {
        uid ??= auth.currentUser?.uid;
        if (uid != null && auth.currentUser != null) {
          await firestore.collection('users').doc(uid).delete();
          await auth.currentUser!.delete();
        }
        await auth.signOut();
        await guestRepository.preferences.remove(
          LocalGuestIdentityRepository.claimKey,
        );
      }
    },
    skip: !const bool.fromEnvironment('AUTH_EMULATORS_TEST'),
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
