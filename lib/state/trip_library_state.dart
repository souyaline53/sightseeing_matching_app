import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/trip_plan.dart';
import '../repository/trips_repository.dart';

final tripsRepositoryProvider = Provider<TripsRepository>(
  (ref) => LocalTripsRepository(),
);
final tripLibraryProvider =
    AsyncNotifierProvider<TripLibraryNotifier, TripLibrary>(
      TripLibraryNotifier.new,
    );
final tripSaveErrorProvider = NotifierProvider<TripSaveErrorNotifier, bool>(
  TripSaveErrorNotifier.new,
);

class TripSaveErrorNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void setFailed(bool failed) => state = failed;
}

class TripLibraryNotifier extends AsyncNotifier<TripLibrary> {
  Future<void> _writes = Future.value();
  @override
  Future<TripLibrary> build() => ref.read(tripsRepositoryProvider).load();
  void upsert(TripState plan) {
    final library = state.requireValue;
    final exists = library.plans.any((p) => p.id == plan.id);
    final plans = [
      for (final p in library.plans) p.id == plan.id ? plan : p,
      if (!exists) plan,
    ];
    _replace(TripLibrary(plans: plans, activeId: plan.id));
  }

  void select(String id) {
    final library = state.requireValue;
    if (!library.plans.any((p) => p.id == id)) return;
    _replace(TripLibrary(plans: library.plans, activeId: id));
  }

  void delete(String id) {
    final library = state.requireValue;
    final remaining = library.plans.where((p) => p.id != id).toList();
    if (remaining.isEmpty) {
      _replace(TripLibrary.empty());
      return;
    }
    _replace(
      TripLibrary(
        plans: remaining,
        activeId: library.activeId == id
            ? remaining.first.id
            : library.activeId,
      ),
    );
  }

  void _replace(TripLibrary next) {
    state = AsyncData(next);
    _persist(next);
  }

  void _persist(TripLibrary next) {
    _writes = _writes
        .then((_) => ref.read(tripsRepositoryProvider).save(next))
        .then(
          (_) {
            if (ref.mounted) {
              ref.read(tripSaveErrorProvider.notifier).setFailed(false);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (ref.mounted) {
              ref.read(tripSaveErrorProvider.notifier).setFailed(true);
            }
          },
        );
  }

  Future<void> retrySave() {
    _persist(state.requireValue);
    return _writes;
  }
}
