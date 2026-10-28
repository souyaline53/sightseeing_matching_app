import 'search_selection_state.dart';
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
  Future<void> saveLast(SearchConditions conditions) => saveSearch(conditions);
  // One repository write keeps a new preset and LastSearch atomic.
  Future<void> saveSearch(SearchConditions conditions, {String? presetName}) =>
      _update((data) {
        final presets = [...data.presets];
        if (presetName != null) {
          presets.add(
            SearchPreset(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              name: presetName.trim().isEmpty ? 'いつもの旅' : presetName.trim(),
              conditions: conditions,
            ),
          );
        }
        return data.copyWith(
          presets: presets,
          lastSearch: LastSearch(
            conditions: conditions,
            searchedAt: DateTime.now().toUtc(),
          ),
        );
      });
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
  void prepareSearch() => ref.read(searchSelectionProvider.notifier).reset();
  @override
  SearchConditions build() => const SearchConditions();
  void replace(SearchConditions conditions) => state = conditions;
}
