import '../state/search_selection_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../state/settings_state.dart';
import '../state/discovery_state.dart';
import '../state/trip_state.dart';
import 'curiosity_questions.dart';

final searchExecutionProvider = Provider((ref) => SearchExecutionService(ref));

class SearchExecutionService {
  final Ref ref;
  bool _running = false;
  SearchExecutionService(this.ref);
  Future<void> execute({String? presetName}) async {
    if (_running) return;
    _running = true;
    try {
      if (!CuriosityQuestions.valid(ref.read(discoveryProvider).interests)) {
        throw StateError('先に3つの質問に回答してください。');
      }
      final selections = ref.read(searchSelectionProvider);
      if (!selections.contains(SearchSelection.length) ||
          !selections.contains(SearchSelection.company)) {
        throw StateError('旅行期間と同行者を選択してください。');
      }
      final filters = ref.read(searchDraftProvider);
      final error = filters.validateFilters();
      if (error != null) throw StateError(error);
      await ref
          .read(settingsProvider.notifier)
          .saveSearch(filters, presetName: presetName);
      ref.read(searchDraftProvider.notifier).replace(filters);
      ref.read(tripProvider.notifier).applySearchFilters(filters);
      ref.read(discoveryProvider.notifier).showExplore();
    } finally {
      _running = false;
    }
  }
}
