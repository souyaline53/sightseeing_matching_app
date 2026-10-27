import 'web_preferences_stub.dart'
    if (dart.library.js_interop) 'web_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/repository/settings_repository.dart';

void main() {
  test('browser preferences survive a new repository instance', () async {
    registerPreferencesForTest();
    final preferences = SharedPreferencesAsync();
    final original = await preferences.getString(
      PreferencesSettingsStorage.key,
    );
    addTearDown(() async {
      if (original == null) {
        await preferences.remove(PreferencesSettingsStorage.key);
      } else {
        await preferences.setString(PreferencesSettingsStorage.key, original);
      }
    });
    final repo = LocalSettingsRepository();
    await repo.save(
      SavedSettings(
        profile: const UserProfile(origin: 'ブラウザ保存確認'),
        presets: const [
          SearchPreset(
            id: 'web',
            name: 'ブラウザの条件',
            conditions: SearchConditions(transport: TravelMode.either),
          ),
        ],
      ),
    );
    final restored = await LocalSettingsRepository().load();
    expect(restored.profile.origin, 'ブラウザ保存確認');
    expect(restored.presets.single.conditions.transport, TravelMode.either);
  }, skip: !kIsWeb);
}
