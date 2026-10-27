import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../state/settings_state.dart';
import '../state/discovery_state.dart';
import '../state/trip_state.dart';

final searchExecutionProvider = Provider((ref) => SearchExecutionService(ref));

class SearchExecutionService {
  final Ref ref;
  bool _running = false;
  SearchExecutionService(this.ref);
  Future<void> execute({bool skipDetails = false}) async {
    if (_running) return;
    _running = true;
    try {
      if (!ref.read(discoveryProvider).interests.complete) {
        throw StateError('先に3つの質問に回答してください。');
      }
      final draft = ref.read(searchDraftProvider.notifier);
      final filters = skipDetails
          ? draft.skippedFilters()
          : ref.read(searchDraftProvider);
      final error = filters.validateFilters();
      if (error != null) throw StateError(error);
      await ref.read(settingsProvider.notifier).saveLast(filters);
      draft.replace(filters);
      ref.read(tripProvider.notifier).applySearchFilters(filters);
      ref.read(discoveryProvider.notifier).showExplore();
    } finally {
      _running = false;
    }
  }
}
