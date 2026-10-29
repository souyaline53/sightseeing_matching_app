import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/mock_data.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'test_support.dart';

void main() {
  test(
    'valid selection takes priority over dates; missing selection falls back safely',
    () {
      final today = DateTime(2026, 10, 29);
      final past = TripState(id: 'past', travelDate: DateTime(2020));
      final next = TripState(id: 'next', travelDate: today);
      final later = TripState(id: 'later', travelDate: DateTime(2026, 12));
      final undated = TripState(id: 'draft', updatedAt: DateTime.utc(2026));
      final recent = TripState(id: 'recent', updatedAt: DateTime.utc(2027));
      expect(
        TripLibrary(plans: [next, past], activeId: past.id).activeTrip!.id,
        'past',
      );
      expect(
        TripLibrary.fallback([later, past, undated, next], today)!.id,
        'next',
      );
      expect(
        TripLibrary.fallback([past, undated, recent], today)!.id,
        'recent',
      );
      expect(TripLibrary.fallback([past], today)!.id, 'past');
      final empty = TripLibrary.fromJson(TripLibrary.empty().toJson());
      expect(empty.plans, isEmpty);
      expect(empty.activeId, isNull);
      expect(empty.activeTrip, isNull);
    },
  );

  test(
    'selection, rename, independent duplication and deletion persist across reloads',
    () async {
      final storage = MemorySettingsStorage();
      final repo = LocalTripsRepository(storage: storage);
      final container = ProviderContainer(
        overrides: [tripsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await container.read(tripLibraryProvider.future);
      final controller = container.read(tripLibraryProvider.notifier);
      final past = TripState(
        title: '昔の旅',
        travelDate: DateTime(2020),
        saved: [experiences[0]],
        stops: [experiences[0]],
      );
      final future = TripState(
        title: 'これからの旅',
        travelDate: DateTime.now().add(const Duration(days: 3)),
        stops: [experiences[1]],
      );
      controller.upsert(future);
      controller.upsert(past);
      await controller.retrySave();
      expect((await repo.load()).activeTrip!.id, past.id);
      controller.rename(future.id, '次の旅');
      expect(
        container.read(tripLibraryProvider).requireValue.activeId,
        past.id,
      );
      expect(() => controller.rename(past.id, '  '), throwsArgumentError);
      controller.duplicate(past.id);
      var library = container.read(tripLibraryProvider).requireValue;
      final copy = library.activeTrip!;
      expect(copy.id, isNot(past.id));
      expect(copy.title, '昔の旅（コピー）');
      expect(identical(copy.stops, past.stops), isFalse);
      expect(identical(copy.stops.first, past.stops.first), isFalse);
      container.read(tripProvider.notifier).toggle(experiences[0]);
      library = container.read(tripLibraryProvider).requireValue;
      expect(library.activeTrip!.stops, isEmpty);
      expect(
        library.plans.firstWhere((p) => p.id == past.id).stops,
        hasLength(1),
      );
      controller.delete(copy.id);
      expect(
        container.read(tripLibraryProvider).requireValue.activeId,
        future.id,
      );
      controller.select(past.id);
      controller.delete(future.id);
      expect(
        container.read(tripLibraryProvider).requireValue.activeId,
        past.id,
      );
      await controller.retrySave();
      final reopened = ProviderContainer(
        overrides: [
          tripsRepositoryProvider.overrideWithValue(
            LocalTripsRepository(storage: storage),
          ),
        ],
      );
      addTearDown(reopened.dispose);
      expect(
        (await reopened.read(tripLibraryProvider.future)).activeId,
        past.id,
      );
      controller.delete(past.id);
      await controller.retrySave();
      expect((await repo.load()).activeId, isNull);
      expect((await repo.load()).plans, isEmpty);
    },
  );

  test(
    'new searches create a plan only on first save and never overwrite existing drafts',
    () async {
      final container = ProviderContainer(
        overrides: [
          tripsRepositoryProvider.overrideWithValue(
            LocalTripsRepository(storage: MemorySettingsStorage()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(tripLibraryProvider.future);
      final controller = container.read(tripProvider.notifier);
      controller.applySearchFilters(const SearchConditions(origin: '小樽駅'));
      controller.applySearchFilters(const SearchConditions(origin: '札幌駅'));
      expect(container.read(tripLibraryProvider).requireValue.plans, isEmpty);
      controller.save(experiences[0]);
      final original = container
          .read(tripLibraryProvider)
          .requireValue
          .activeTrip!;
      controller.applySearchFilters(const SearchConditions(origin: '旭川駅'));
      expect(
        container.read(tripLibraryProvider).requireValue.activeId,
        original.id,
      );
      expect(
        container.read(tripLibraryProvider).requireValue.plans,
        hasLength(1),
      );
      controller.save(experiences[1]);
      final library = container.read(tripLibraryProvider).requireValue;
      expect(library.plans, hasLength(2));
      expect(library.activeTrip!.origin, '旭川駅');
      expect(
        library.plans.firstWhere((p) => p.id == original.id).toJson(),
        original.toJson(),
      );
      await container.read(tripLibraryProvider.notifier).retrySave();
    },
  );
}
