import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/trip_plan.dart';
import 'settings_repository.dart';

abstract interface class TripsRepository {
  Future<TripLibrary> load();
  Future<void> save(TripLibrary library);
}

class LocalTripsRepository implements TripsRepository {
  final SettingsStorage storage;
  LocalTripsRepository({SettingsStorage? storage})
    : storage = storage ?? _TripStorage();
  @override
  Future<TripLibrary> load() async {
    final raw = await storage.read();
    if (raw == null) return TripLibrary.empty();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final library = TripLibrary.fromJson(data);
    if (data['activeId'] != library.activeId) await save(library);
    return library;
  }

  @override
  Future<void> save(TripLibrary library) =>
      storage.write(jsonEncode(library.toJson()));
}

class _TripStorage implements SettingsStorage {
  static const key = 'tabisaki.trips.v1';
  final preferences = SharedPreferencesAsync();
  @override
  Future<String?> read() => preferences.getString(key);
  @override
  Future<void> write(String value) => preferences.setString(key, value);
}
