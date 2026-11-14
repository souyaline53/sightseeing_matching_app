import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/transport.dart';
import '../service/transport/ai_trip_repository.dart';

final aiSetupIntentProvider = NotifierProvider<AiSetupIntent, int>(
  AiSetupIntent.new,
);

class AiSetupIntent extends Notifier<int> {
  @override
  int build() => 0;
  void open() => state++;
  void clear() => state = 0;
}

final aiRestoreIntentProvider = NotifierProvider<AiSetupIntent, int>(
  AiSetupIntent.new,
);
final aiRefreshIntentProvider = NotifierProvider<AiSetupIntent, int>(
  AiSetupIntent.new,
);

final aiTripDocumentProvider = StreamProvider.family<Json, String>(
  (ref, id) => ref.watch(aiTripRepositoryProvider).watch(id),
);
