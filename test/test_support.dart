import 'package:sightseeing_matching_app/repository/settings_repository.dart';

class MemorySettingsStorage implements SettingsStorage {
  String? value;
  bool failRead = false, failWrite = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('read unavailable');
    return value;
  }

  @override
  Future<void> write(String value) async {
    if (failWrite) throw StateError('write unavailable');
    this.value = value;
  }
}
