import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/search_settings.dart';

abstract interface class SettingsRepository {
  Future<SavedSettings> load();
  Future<void> save(SavedSettings settings);
}

/// A small seam for exercising the exact JSON repository without platform I/O.
abstract interface class SettingsStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class PreferencesSettingsStorage implements SettingsStorage {
  static const key = 'tabisaki.settings.v1';
  final SharedPreferencesAsync preferences;
  PreferencesSettingsStorage({SharedPreferencesAsync? preferences})
    : preferences = preferences ?? SharedPreferencesAsync();
  @override
  Future<String?> read() => preferences.getString(key);
  @override
  Future<void> write(String value) => preferences.setString(key, value);
}

class LocalSettingsRepository implements SettingsRepository {
  final SettingsStorage storage;
  LocalSettingsRepository({SettingsStorage? storage})
    : storage = storage ?? PreferencesSettingsStorage();
  @override
  Future<SavedSettings> load() async {
    final raw = await storage.read();
    return raw == null
        ? SavedSettings()
        : SavedSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(SavedSettings settings) =>
      storage.write(jsonEncode(settings.toJson()));
}
