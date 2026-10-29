import '../model/account_profile.dart';

abstract interface class AccountRepository {
  bool get available;
  String? get unavailableMessage;
  Stream<AccountIdentity> watchIdentity();
  Stream<AccountDetails?> watchProfile(String uid);
  Future<void> register({
    required String email,
    required String password,
    required AccountDetails details,
  });
  Future<void> signIn(String email, String password);
  Future<void> saveProfile(AccountDetails details);
  Future<void> signOut();
  Future<void> resetPassword(String email);
  Future<void> sendVerification();
  Future<void> reloadIdentity();
}

class GuestAccountRepository implements AccountRepository {
  final GuestIdentity guest;
  @override
  final String unavailableMessage;
  GuestAccountRepository(this.guest, this.unavailableMessage);
  @override
  bool get available => false;
  @override
  Stream<AccountIdentity> watchIdentity() =>
      Stream.value(AccountIdentity(uid: guest.id));
  @override
  Stream<AccountDetails?> watchProfile(String uid) => Stream.value(null);
  Never _unavailable() => throw AccountFailure(unavailableMessage);
  @override
  Future<void> register({
    required String email,
    required String password,
    required AccountDetails details,
  }) async => _unavailable();
  @override
  Future<void> signIn(String email, String password) async => _unavailable();
  @override
  Future<void> saveProfile(AccountDetails details) async => _unavailable();
  @override
  Future<void> signOut() async {}
  @override
  Future<void> resetPassword(String email) async => _unavailable();
  @override
  Future<void> sendVerification() async => _unavailable();
  @override
  Future<void> reloadIdentity() async {}
}
