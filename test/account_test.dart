import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/japan_regions.dart';
import 'package:sightseeing_matching_app/model/account_profile.dart';
import 'package:sightseeing_matching_app/state/account_state.dart';
import 'test_support.dart';

const details = AccountDetails(
  nickname: 'たびすけ',
  ageGroup: '30代',
  prefecture: '北海道',
  municipality: '札幌市',
);
void main() {
  test(
    'all 47 prefectures are available by region; profile attributes exclude credentials',
    () {
      final prefectures = japanRegions.values
          .expand((values) => values)
          .toList();
      expect(prefectures, hasLength(47));
      expect(prefectures.toSet(), hasLength(47));
      expect(regionForPrefecture('北海道'), '北海道');
      expect(regionForPrefecture('東京都'), '関東');
      expect(details.validate(), isNull);
      expect(AccountDetails.fromMap(details.toMap()).toMap(), details.toMap());
      expect(details.toMap().containsKey('password'), isFalse);
      expect(details.toMap().containsKey('email'), isFalse);
      expect(
        const AccountDetails(
          nickname: ' ',
          ageGroup: '30代',
          prefecture: '北海道',
          municipality: '札幌市',
        ).validate(),
        isNotNull,
      );
      expect(
        const AccountDetails(
          nickname: '旅',
          ageGroup: '',
          prefecture: '北海道',
          municipality: '札幌市',
        ).validate(),
        isNotNull,
      );
      expect(
        const AccountDetails(
          nickname: '旅',
          ageGroup: '30代',
          prefecture: '架空県',
          municipality: '札幌市',
        ).validate(),
        isNotNull,
      );
    },
  );
  test(
    'registration and logout change identity without requiring registration for guest use',
    () async {
      final guest = MemoryGuestIdentityRepository(
        const GuestIdentity('guest-test'),
      );
      final repository = FakeAccountRepository(guestUid: 'guest-test');
      final container = ProviderContainer(
        overrides: [
          guestIdentityRepositoryProvider.overrideWithValue(guest),
          accountRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
      addTearDown(container.dispose);
      container.listen(currentAccountProvider, (_, _) {});
      await container.read(accountIdentityProvider.future);
      await container.read(guestIdentityProvider.future);
      expect(container.read(currentAccountProvider).name, 'ゲストさん');
      expect(container.read(currentAccountProvider).identity.uid, 'guest-test');
      await container
          .read(accountActionsProvider)
          .register(
            email: 'test@example.com',
            password: 'abcdef',
            details: details,
          );
      await container.read(accountDetailsProvider('firebase-uid-test').future);
      await container.pump();
      final registered = container.read(currentAccountProvider);
      expect(registered.registered, isTrue);
      expect(registered.name, 'たびすけ');
      expect(registered.identity.uid, 'firebase-uid-test');
      expect(repository.lastPassword, 'abcdef');
      await container.read(accountActionsProvider).signOut();
      await container.pump();
      expect(container.read(currentAccountProvider).name, 'ゲストさん');
      expect(container.read(currentAccountProvider).registered, isFalse);
    },
  );
  test('cloud posts belong only to the exact Firebase UID', () {
    const alice = CurrentAccount(
      identity: AccountIdentity(uid: 'alice', registered: true),
    );
    const bob = CurrentAccount(
      identity: AccountIdentity(uid: 'bob', registered: true),
    );
    expect(alice.ownsPost('guest-test'), isFalse);
    expect(alice.ownsPost('local-user'), isFalse);
    expect(alice.ownsPost('alice'), isTrue);
    expect(bob.ownsPost('guest-test'), isFalse);
    expect(bob.ownsPost('alice'), isFalse);
    expect(bob.ownsPost('bob'), isTrue);
  });
}
