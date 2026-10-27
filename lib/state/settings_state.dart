import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/search_settings.dart';
import '../repository/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => LocalSettingsRepository(),
);
final settingsProvider = AsyncNotifierProvider<SettingsNotifier, SavedSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<SavedSettings> {
  Future<void> _queue = Future.value();
  @override
  Future<SavedSettings> build() => ref.read(settingsRepositoryProvider).load();
  Future<void> _update(SavedSettings Function(SavedSettings) transform) {
    final operation = _queue.then((_) async {
      final current = await future;
      final next = transform(current);
      await ref.read(settingsRepositoryProvider).save(next);
      state = AsyncData(next);
    });
    _queue = operation.then(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }

  Future<void> saveProfile(UserProfile profile) =>
      _update((data) => data.copyWith(profile: profile));
  Future<void> saveLast(SearchConditions conditions) => _update(
    (data) => data.copyWith(
      lastSearch: LastSearch(
        conditions: conditions,
        searchedAt: DateTime.now().toUtc(),
      ),
    ),
  );
  Future<void> savePreset(
    SearchConditions conditions,
    String name, {
    String? id,
  }) => _update((data) {
    final preset = SearchPreset(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'いつもの旅' : name.trim(),
      conditions: conditions,
    );
    return data.copyWith(
      presets: [...data.presets.where((e) => e.id != preset.id), preset],
    );
  });
  Future<void> deletePreset(String id) => _update(
    (data) =>
        data.copyWith(presets: data.presets.where((e) => e.id != id).toList()),
  );
}

final searchDraftProvider =
    NotifierProvider<SearchDraftNotifier, SearchConditions>(
      SearchDraftNotifier.new,
    );

class SearchDraftNotifier extends Notifier<SearchConditions> {
  SearchConditions _initial = const SearchConditions();
  void captureInitial() => _initial = state;
  SearchConditions get initialFilters => _initial;
  SearchConditions skippedFilters() =>
      _initial.copyWith(origin: state.origin, transport: state.transport);
  @override
  SearchConditions build() => const SearchConditions();
  void replace(SearchConditions conditions) => state = conditions;
}
