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
            ? TripLibrary.fallback(remaining)?.id
            : library.activeId,
      ),
    );
  }

  void rename(String id, String title) {
    final name = title.trim();
    if (name.isEmpty) throw ArgumentError('旅行タイトルを入力してください。');
    final library = state.requireValue;
    _replace(
      TripLibrary(
        plans: [
          for (final p in library.plans)
            p.id == id ? p.copyWith(title: name) : p,
        ],
        activeId: library.activeId,
      ),
    );
  }

  void duplicate(String id) {
    final original = state.requireValue.plans
        .where((p) => p.id == id)
        .firstOrNull;
    if (original == null) return;
    // JSON round-trip also copies nested lists and experience records.
    final data = original.toJson();
    data['id'] = TripState().id;
    data['title'] = '${original.displayTitle}（コピー）';
    data['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    upsert(TripState.fromJson(data));
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
