import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Presentation state only; all three pages edit the same searchDraftProvider.
final conditionsStepProvider = NotifierProvider<ConditionsStepNotifier, int>(
  ConditionsStepNotifier.new,
);

class ConditionsStepNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void reset() => state = 0;
  void next() {
    if (state < 2) state++;
  }

  void back() {
    if (state > 0) state--;
  }
}
