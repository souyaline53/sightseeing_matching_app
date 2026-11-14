import '../service/transport/ai_trip_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/trip_plan.dart';
import '../model/experience.dart';
import '../repository/trips_repository.dart';

final tripsRepositoryProvider = Provider<TripsRepository>(
  (ref) => LocalTripsRepository(),
);
final tripLibraryProvider =
    AsyncNotifierProvider<TripLibraryNotifier, TripLibrary>(
      TripLibraryNotifier.new,
    );

/// Favorites belong to the library, independently of any completed itinerary.
final savedExperiencesProvider = Provider<List<Experience>>(
  (ref) => ref.watch(tripLibraryProvider).value?.savedSpots ?? const [],
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
  Future<void> flush() => _writes;
  void upsert(TripState plan) {
    final library = state.requireValue;
    final exists = library.plans.any((p) => p.id == plan.id);
    final plans = [
      for (final p in library.plans) p.id == plan.id ? plan : p,
      if (!exists) plan,
    ];
    _replace(
      TripLibrary(
        plans: plans,
        activeId: plan.id,
        savedSpots: library.savedSpots,
      ),
    );
  }

  void saveExperience(Experience spot) {
    final library = state.requireValue;
    if (library.savedSpots.any((e) => e.id == spot.id)) return;
    _setSaved([...library.savedSpots, spot]);
  }

  void toggleExperience(Experience spot) {
    final saved = state.requireValue.savedSpots;
    _setSaved(
      saved.any((e) => e.id == spot.id)
          ? saved.where((e) => e.id != spot.id).toList()
          : [...saved, spot],
    );
  }

  void _setSaved(List<Experience> saved) {
    final library = state.requireValue;
    _replace(
      TripLibrary(
        plans: library.plans,
        activeId: library.activeId,
        savedSpots: saved,
      ),
      saveActive: false,
    );
  }

  void select(String id) {
    final library = state.requireValue;
    if (!library.plans.any((p) => p.id == id)) return;
    _replace(
      TripLibrary(
        plans: library.plans,
        activeId: id,
        savedSpots: library.savedSpots,
      ),
    );
  }

  void delete(String id) {
    final library = state.requireValue;
    final remaining = library.plans.where((p) => p.id != id).toList();
    if (remaining.isEmpty) {
      _replace(TripLibrary(plans: [], savedSpots: library.savedSpots));
      return;
    }
    _replace(
      TripLibrary(
        plans: remaining,
        savedSpots: library.savedSpots,
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
        savedSpots: library.savedSpots,
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
    data['ai'] = {
      ...original.ai,
      'lineage': original.ai['lineage'] ?? original.id,
    };
    data['id'] = TripState().id;
    data['title'] = '${original.displayTitle}（コピー）';
    data['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    upsert(TripState.fromJson(data));
  }

  void _replace(TripLibrary next, {bool saveActive = true}) {
    state = AsyncData(next);
    _persist(next, saveActive: saveActive);
  }

  void _persist(TripLibrary next, {bool saveActive = true}) {
    _writes = _writes
        .then((_) => _save(next, saveActive: saveActive))
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

  Future<void> _save(TripLibrary next, {bool saveActive = true}) async {
    await ref.read(tripsRepositoryProvider).save(next);
    final active = next.activeTrip;
    if (saveActive && active != null && active.ai['rootId'] != null) {
      await ref.read(aiTripRepositoryProvider).save(active);
    }
  }

  Future<void> retrySave() {
    _persist(state.requireValue);
    return _writes;
  }
}
