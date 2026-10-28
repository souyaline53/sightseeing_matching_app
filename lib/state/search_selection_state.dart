import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tracks explicit choices separately from the stored filter defaults.
enum SearchSelection { origin, transport, length, company, walking }

final searchSelectionProvider =
    NotifierProvider<SearchSelectionNotifier, Set<SearchSelection>>(
      SearchSelectionNotifier.new,
    );

class SearchSelectionNotifier extends Notifier<Set<SearchSelection>> {
  @override
  Set<SearchSelection> build() => const {};
  void reset() => state = const {};
  void choose(SearchSelection field) =>
      state = Set.unmodifiable({...state, field});
}
