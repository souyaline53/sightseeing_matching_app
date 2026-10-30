import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/account_profile.dart';
import '../../state/account_state.dart';

const adminEmail = 'nichi-ka@nichi-ka.com';
bool isAdminIdentity(AccountIdentity identity) =>
    identity.registered && identity.email?.toLowerCase() == adminEmail;
final isAdminProvider = Provider<bool>(
  (ref) => isAdminIdentity(ref.watch(currentAccountProvider).identity),
);

class CloudServices {
  final FirebaseFirestore firestore;
  final FirebaseStorage storage;
  final FirebaseAuth auth;
  CloudServices(this.firestore, this.storage, this.auth);
  Future<User> writer() async {
    try {
      return auth.currentUser ?? (await auth.signInAnonymously()).user!;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'operation-not-allowed' ||
          error.code == 'admin-restricted-operation') {
        throw StateError(
          'ゲストの写真投稿にはFirebaseの匿名認証を有効にしてください。登録済みの場合はログインして投稿できます。',
        );
      }
      rethrow;
    }
  }

  void requireAdmin() {
    final user = auth.currentUser;
    if (user == null ||
        user.isAnonymous ||
        user.email?.toLowerCase() != adminEmail ||
        !user.emailVerified) {
      throw StateError('管理者アカウントでログインし、メールアドレスの確認を完了してください。');
    }
  }
}

final cloudServicesProvider = FutureProvider<CloudServices>((ref) async {
  final runtime = await ref.watch(firebaseRuntimeProvider.future);
  if (!runtime.available) throw StateError(runtime.message!);
  return CloudServices(
    FirebaseFirestore.instance,
    FirebaseStorage.instance,
    FirebaseAuth.instance,
  );
});
