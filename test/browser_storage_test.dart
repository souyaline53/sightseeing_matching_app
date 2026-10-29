import 'web_preferences_stub.dart'
    if (dart.library.js_interop) 'web_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/repository/settings_repository.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';

void main() {
  test(
    'browser trip selection and empty library survive a new repository',
    () async {
      registerPreferencesForTest();
      final preferences = SharedPreferencesAsync();
      const key = 'tabisaki.trips.v1';
      final original = await preferences.getString(key);
      addTearDown(() async {
        if (original == null) {
          await preferences.remove(key);
        } else {
          await preferences.setString(key, original);
        }
      });
      final past = TripState(
        id: 'past',
        title: '選択した旅',
        travelDate: DateTime(2020),
      );
      final future = TripState(id: 'future', travelDate: DateTime(2099));
      await LocalTripsRepository().save(
        TripLibrary(plans: [future, past], activeId: past.id),
      );
      final restored = await LocalTripsRepository().load();
      expect(restored.activeTrip!.id, 'past');
      expect(restored.plans, hasLength(2));
      await LocalTripsRepository().save(TripLibrary.empty());
      expect((await LocalTripsRepository().load()).activeId, isNull);
      expect((await LocalTripsRepository().load()).plans, isEmpty);
    },
    skip: !kIsWeb,
  );

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
