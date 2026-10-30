import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/account_profile.dart';
import '../repository/account_repository.dart';
import '../repository/firebase_account_repository.dart';
import '../repository/guest_identity_repository.dart';
import '../service/auth/firebase_runtime.dart';

final guestIdentityRepositoryProvider = Provider<GuestIdentityRepository>(
  (ref) => LocalGuestIdentityRepository(),
);
final guestIdentityProvider = FutureProvider<GuestIdentity>(
  (ref) => ref.watch(guestIdentityRepositoryProvider).load(),
);
final firebaseRuntimeProvider = FutureProvider<FirebaseRuntime>(
  (ref) => initializeAccountFirebase(),
);
final accountRepositoryProvider = FutureProvider<AccountRepository>((
  ref,
) async {
  final guest = await ref.watch(guestIdentityProvider.future);
  final runtime = await ref.watch(firebaseRuntimeProvider.future);
  if (!runtime.available) {
    return GuestAccountRepository(guest, runtime.message!);
  }
  return FirebaseAccountRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
    guest: guest,
  );
});
final accountIdentityProvider = StreamProvider<AccountIdentity>((ref) async* {
  final repository = await ref.watch(accountRepositoryProvider.future);
  yield* repository.watchIdentity();
});
final accountDetailsProvider = StreamProvider.family<AccountDetails?, String>((
  ref,
  uid,
) async* {
  final repository = await ref.watch(accountRepositoryProvider.future);
  yield* repository.watchProfile(uid);
});
final currentAccountProvider = Provider<CurrentAccount>((ref) {
  final guest = ref.watch(guestIdentityProvider);
  final identity = ref.watch(accountIdentityProvider);
  final user =
      identity.value ??
      AccountIdentity(uid: guest.value?.id ?? 'guest-loading');
  final profile = user.registered
      ? ref.watch(accountDetailsProvider(user.uid))
      : const AsyncData<AccountDetails?>(null);
  return CurrentAccount(
    identity: user,
    details: profile.value,
    loading: identity.isLoading || guest.isLoading,
    profileLoading: profile.isLoading,
    error: identity.error ?? profile.error ?? guest.error,
  );
});
final accountActionsProvider = Provider((ref) => AccountActions(ref));

class AccountActions {
  final Ref ref;
  AccountActions(this.ref);
  Future<void> register({
    required String email,
    required String password,
    required AccountDetails details,
  }) async {
    final repository = await ref.read(accountRepositoryProvider.future);
    await repository.register(
      email: email,
      password: password,
      details: details,
    );
  }

  Future<void> signIn(String email, String password) async {
    final repository = await ref.read(accountRepositoryProvider.future);
    await repository.signIn(email, password);
  }

  Future<void> saveProfile(AccountDetails details) async {
    final repository = await ref.read(accountRepositoryProvider.future);
    await repository.saveProfile(details);
  }

  Future<void> signOut() async =>
      (await ref.read(accountRepositoryProvider.future)).signOut();
  Future<void> resetPassword(String email) async =>
      (await ref.read(accountRepositoryProvider.future)).resetPassword(email);
  Future<void> sendVerification() async =>
      (await ref.read(accountRepositoryProvider.future)).sendVerification();
  Future<void> reloadIdentity() async =>
      (await ref.read(accountRepositoryProvider.future)).reloadIdentity();
}
