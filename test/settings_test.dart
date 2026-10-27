import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/repository/settings_repository.dart';
import 'package:sightseeing_matching_app/state/settings_state.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'package:sightseeing_matching_app/data/mock_data.dart';
import 'package:sightseeing_matching_app/service/curiosity_questions.dart';
import 'package:sightseeing_matching_app/service/recommendation_service.dart';
import 'test_support.dart';

void main() {
  test(
    'JSON repository restores all three data types in a new provider container',
    () async {
      final storage = MemorySettingsStorage();
      ProviderContainer open() => ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            LocalSettingsRepository(storage: storage),
          ),
        ],
      );
      final first = open();
      await first.read(settingsProvider.future);
      final controller = first.read(settingsProvider.notifier);
      await controller.saveProfile(
        const UserProfile(
          origin: '小樽駅',
          transport: TravelMode.either,
          budget: 25000,
          walking: Walking.light,
        ),
      );
      const a = SearchConditions(
        origin: '旭川駅',
        budget: 12000,
        dateChoice: DateChoice.weekend,
        company: Company.family,
        length: TripLength.overnight,
        maxMinutes: 90,
      );
      const b = SearchConditions(
        origin: '札幌駅',
        transport: TravelMode.car,
        dateChoice: DateChoice.fixed,
        fixedDate: null,
      );
      await Future.wait([
        controller.savePreset(a, '家族の週末', id: 'a'),
        controller.savePreset(b, 'ドライブ', id: 'b'),
      ]);
      await controller.saveLast(a);
      first.dispose();
      final restored = open();
      addTearDown(restored.dispose);
      final data = await restored.read(settingsProvider.future);
      expect(data.profile.origin, '小樽駅');
      expect(data.profile.transport, TravelMode.either);
      expect(data.presets.length, 2);
      expect(data.presets.first.conditions.length, TripLength.overnight);
      expect(data.presets.first.conditions.company, Company.family);
      expect(data.presets.first.conditions.maxMinutes, 90);
      expect(data.lastSearch!.conditions.toJson(), a.toJson());
      await restored
          .read(settingsProvider.notifier)
          .savePreset(a.copyWith(origin: '千歳駅'), '新しい名前', id: 'a');
      var changed = restored.read(settingsProvider).requireValue;
      expect(changed.profile.origin, '小樽駅');
      expect(changed.lastSearch!.conditions.origin, '旭川駅');
      expect(
        changed.presets.firstWhere((e) => e.id == 'b').conditions.origin,
        '札幌駅',
      );
      expect(changed.presets.firstWhere((e) => e.id == 'a').name, '新しい名前');
      await restored.read(settingsProvider.notifier).deletePreset('b');
      changed = await LocalSettingsRepository(storage: storage).load();
      expect(changed.presets.single.id, 'a');
      expect(() => changed.presets.clear(), throwsUnsupportedError);
    },
  );
  test(
    'failed save is not reported as success and subsequent writes recover',
    () async {
      final storage = MemorySettingsStorage();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            LocalSettingsRepository(storage: storage),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      storage.failWrite = true;
      await expectLater(
        container
            .read(settingsProvider.notifier)
            .saveProfile(const UserProfile(origin: '失敗')),
        throwsStateError,
      );
      expect(
        container.read(settingsProvider).requireValue.profile.origin,
        '札幌駅',
      );
      storage.failWrite = false;
      await container
          .read(settingsProvider.notifier)
          .saveProfile(const UserProfile(origin: '小樽駅'));
      expect(
        container.read(settingsProvider).requireValue.profile.origin,
        '小樽駅',
      );
    },
  );
  test('malformed stored JSON is not silently overwritten', () async {
    final storage = MemorySettingsStorage()..value = '{broken';
    final repo = LocalSettingsRepository(storage: storage);
    await expectLater(repo.load(), throwsFormatException);
    expect(storage.value, '{broken');
  });
  test('relative dates recompute and past fixed dates require correction', () {
    const tomorrow = SearchConditions();
    expect(
      tomorrow.resolveDate(DateTime(2026, 10, 27)),
      DateTime(2026, 10, 28),
    );
    expect(
      tomorrow.resolveDate(DateTime(2026, 10, 30)),
      DateTime(2026, 10, 31),
    );
    const weekend = SearchConditions(dateChoice: DateChoice.weekend);
    expect(weekend.resolveDate(DateTime(2026, 10, 27)), DateTime(2026, 10, 31));
    expect(weekend.resolveDate(DateTime(2026, 11, 1)), DateTime(2026, 11, 7));
    final past = SearchConditions(
      dateChoice: DateChoice.fixed,
      fixedDate: DateTime(2020),
    );
    expect(past.validate(DateTime(2026)), contains('過去'));
    expect(const SearchConditions(origin: '').validate(), contains('出発地'));
  });
  test(
    'all 24 answer combinations broaden interests and affect recommendation order',
    () {
      final service = RecommendationService();
      for (var mood = 0; mood < moods.length; mood++) {
        final orders = <String>{};
        expect(CuriosityQuestions.reason(mood).choices.length, 2);
        for (var reason = 0; reason < 2; reason++) {
          final q = CuriosityQuestions.broaden(mood, reason);
          expect(q.choices.length, 2);
          expect(q.title, isNotEmpty);
          for (var broaden = 0; broaden < 2; broaden++) {
            final deck = service.recommend(moods[mood].$2, [reason, broaden]);
            expect(deck.first.category, moods[mood].$2);
            expect(deck[1].category, isNot(moods[mood].$2));
            expect(deck.map((e) => e.id).toSet().length, experiences.length);
            orders.add(deck.map((e) => e.id).join(','));
          }
        }
        expect(orders.length, 4, reason: 'mood $mood');
      }
    },
  );
  test(
    'question back preserves answers; changing an earlier answer clears stale branches',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(discoveryProvider.notifier);
      controller.startConditions();
      controller.startQuestions();
      controller.selectMood(0);
      controller.answer(0);
      controller.answer(1);
      controller.showExplore();
      controller.back();
      expect(container.read(discoveryProvider).question, 2);
      expect(container.read(discoveryProvider).answers, [0, 1]);
      controller.back();
      controller.answer(1);
      expect(container.read(discoveryProvider).answers, [1]);
      controller.answer(0);
      controller.showExplore();
      controller.goTo(9);
      controller.advance();
      expect(container.read(discoveryProvider).index, 0);
    },
  );
  test(
    'trip editing preserves saved cards and search conditions remain independent',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final trip = container.read(tripProvider.notifier);
      const c = SearchConditions(
        origin: '小樽駅',
        transport: TravelMode.either,
        budget: 15000,
        length: TripLength.longer,
      );
      trip.applyConditions(c);
      trip.save(experiences[0]);
      trip.save(experiences[1]);
      trip.save(experiences[0]);
      trip.reorder(0, 2);
      expect(container.read(tripProvider).stops.first.id, experiences[1].id);
      expect(container.read(tripProvider).saved.length, 2);
      trip.removeStop(experiences[0]);
      trip.addStop(experiences[0]);
      trip.setOrigin('千歳駅');
      expect(c.origin, '小樽駅');
      expect(container.read(tripProvider).conditions.length, TripLength.longer);
      expect(
        container.read(tripProvider).conditions.transport,
        TravelMode.either,
      );
    },
  );
}
