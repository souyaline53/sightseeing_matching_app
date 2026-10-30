import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/account_profile.dart';
import 'account_repository.dart';

class FirebaseAccountRepository implements AccountRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final GuestIdentity guest;
  FirebaseAccountRepository({
    required this.auth,
    required this.firestore,
    required this.guest,
  });
  @override
  bool get available => true;
  @override
  String? get unavailableMessage => null;
  @override
  Stream<AccountIdentity> watchIdentity() => auth.userChanges().map(
    (user) => user == null || user.isAnonymous
        ? AccountIdentity(uid: user?.uid ?? guest.id)
        : AccountIdentity(
            uid: user.uid,
            email: user.email,
            registered: true,
            displayName: user.displayName?.trim().isNotEmpty == true
                ? user.displayName!
                : 'プロフィール未登録',
            emailVerified: user.emailVerified,
          ),
  );
  @override
  Stream<AccountDetails?> watchProfile(String uid) =>
      firestore.collection('users').doc(uid).snapshots().map((snapshot) {
        final data = snapshot.data();
        return data == null ? null : AccountDetails.fromMap(data);
      });
  @override
  Future<void> register({
    required String email,
    required String password,
    required AccountDetails details,
  }) async {
    final error = details.validate();
    if (error != null) throw AccountFailure(error);
    if (password.length < 6) throw const AccountFailure('パスワードは6文字以上にしてください。');
    try {
      final current = auth.currentUser;
      if (current == null) {
        await auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
      } else if (current.isAnonymous) {
        await current.linkWithCredential(
          EmailAuthProvider.credential(email: email.trim(), password: password),
        );
      } else if (current.email?.toLowerCase() != email.trim().toLowerCase()) {
        throw const AccountFailure('別のアカウントでログイン中です。プロフィール画面から確認してください。');
      }
    } on FirebaseAuthException catch (error) {
      throw AccountFailure(authErrorMessage(error.code));
    }
    try {
      await saveProfile(details);
    } catch (_) {
      throw const AccountFailure(
        'アカウントは作成済みですが、プロフィールを保存できませんでした。設定を確認して再度「登録する」を押すか、「登録を完了する」から続けてください。',
      );
    }
  }

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw AccountFailure(authErrorMessage(error.code));
    }
  }

  @override
  Future<void> saveProfile(AccountDetails details) async {
    final error = details.validate();
    if (error != null) throw AccountFailure(error);
    final user = auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw const AccountFailure('ログインしてください。');
    }
    final reference = firestore.collection('users').doc(user.uid);
    await firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      transaction.set(reference, {
        'uid': user.uid,
        ...details.toMap(),
        'createdAt':
            existing.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    await user.updateDisplayName(details.nickname.trim());
  }

  @override
  Future<void> signOut() => auth.signOut();
  @override
  Future<void> resetPassword(String email) async {
    try {
      await auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw AccountFailure(authErrorMessage(error.code));
    }
  }

  @override
  Future<void> sendVerification() async {
    final user = auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw const AccountFailure('ログインしてください。');
    }
    await user.sendEmailVerification();
  }

  @override
  Future<void> reloadIdentity() async {
    final user = auth.currentUser;
    if (user != null) {
      await user.reload();
      await auth.currentUser?.getIdToken(true);
    }
  }
}

String authErrorMessage(String code) => switch (code) {
  'email-already-in-use' => 'このメールアドレスは登録済みです。ログインしてください。',
  'invalid-email' => 'メールアドレスの形式を確認してください。',
  'weak-password' => 'パスワードは6文字以上にしてください。Firebase側のパスワードポリシーも確認してください。',
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' => 'メールアドレスまたはパスワードを確認してください。',
  'operation-not-allowed' ||
  'configuration-not-found' => 'Firebase Authenticationのメール/パスワード認証を有効にしてください。',
  'network-request-failed' => '通信できませんでした。ネットワークを確認してください。',
  'too-many-requests' => '試行回数が多いため、少し時間をおいて再度お試しください。',
  'user-disabled' => 'このアカウントは無効になっています。',
  _ => '認証処理に失敗しました。時間をおいて再度お試しください。',
};
