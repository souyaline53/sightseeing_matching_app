import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/account_profile.dart';

abstract interface class GuestIdentityRepository {
  Future<GuestIdentity> load();
  Future<void> claim(String uid);
}

class LocalGuestIdentityRepository implements GuestIdentityRepository {
  static const idKey = 'tabisaki.guest.id.v1';
  static const claimKey = 'tabisaki.guest.owner.v1';
  final SharedPreferencesAsync preferences;
  LocalGuestIdentityRepository({SharedPreferencesAsync? preferences})
    : preferences = preferences ?? SharedPreferencesAsync();
  @override
  Future<GuestIdentity> load() async {
    var id = await preferences.getString(idKey);
    if (id == null) {
      final random = Random.secure();
      id =
          'guest-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      await preferences.setString(idKey, id);
    }
    return GuestIdentity(
      id,
      claimedByUid: await preferences.getString(claimKey),
    );
  }

  @override
  Future<void> claim(String uid) async {
    if (await preferences.getString(claimKey) == null) {
      await preferences.setString(claimKey, uid);
    }
  }
}
