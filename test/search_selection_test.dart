import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/repository/settings_repository.dart';
import 'package:sightseeing_matching_app/screen/search/conditions_step_pages.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:sightseeing_matching_app/state/search_selection_state.dart';
import 'package:sightseeing_matching_app/state/settings_state.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot, answerQuestions, reveal;

Iterable<Semantics> selectedCards(WidgetTester tester, Type page) => tester
    .widgetList<Semantics>(
      find.descendant(of: find.byType(page), matching: find.byType(Semantics)),
    )
    .where((widget) => widget.properties.selected == true);

void main() {
  testWidgets(
    'search starts visually unselected, preserves defaults and remembers explicit choices on back',
    (tester) async {
      final storage = MemorySettingsStorage();
      await LocalSettingsRepository(storage: storage).save(
        SavedSettings(
          profile: const UserProfile(
            origin: '小樽駅',
            transport: TravelMode.either,
            walking: Walking.plenty,
            budget: 23000,
          ),
        ),
      );
      final container = await boot(tester, storage: storage);
      await tester.tap(find.text('新しい旅を探す'));
      await tester.pumpAndSettle();
      expect(container.read(discoveryProvider).interests.moodSelected, isFalse);
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where(
              (s) =>
                  s.properties.selected == true && s.properties.button == true,
            ),
        isEmpty,
      );
      await answerQuestions(tester, mood: 2);
      expect(container.read(discoveryProvider).interests.moodSelected, isTrue);
      expect(container.read(searchDraftProvider).origin, '小樽駅');
      expect(selectedCards(tester, DepartureStepPage), isEmpty);
      await tester.tap(find.byKey(const ValueKey('origin-chip-札幌駅')));
      await tester.pumpAndSettle();
      expect(container.read(searchDraftProvider).transport, TravelMode.either);
      expect(selectedCards(tester, TransportStepPage), isEmpty);
      await tester.tap(find.byKey(const ValueKey('travel-car')));
      await tester.pumpAndSettle();
      expect(selectedCards(tester, TripLengthStepPage), isEmpty);
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .every((chip) => !chip.selected),
        isTrue,
      );
      expect(container.read(searchDraftProvider).budget, 23000);
      await tester.tap(find.text('日帰り'));
      await tester.pumpAndSettle();
      expect(selectedCards(tester, CompanionStepPage), isEmpty);
      await reveal(tester, find.byKey(const ValueKey('company-family')));
      await tester.tap(find.byKey(const ValueKey('company-family')));
      await tester.pumpAndSettle();
      expect(selectedCards(tester, CompanionStepPage).length, 1); // Companion.
      await reveal(tester, find.text('さらに細かく設定'));
      await tester.tap(find.text('さらに細かく設定'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('多め'));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '多め'))
            .selected,
        isFalse,
      );
      expect(container.read(searchDraftProvider).walking, Walking.plenty);
      await tester.tap(find.text('少なめ'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '少なめ'))
            .selected,
        isTrue,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(selectedCards(tester, TripLengthStepPage).length, 1);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(selectedCards(tester, TransportStepPage).length, 1);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(selectedCards(tester, DepartureStepPage).length, 1);
      container.read(discoveryProvider.notifier).reset();
      await tester.pumpAndSettle();
      await tester.tap(find.text('新しい旅を探す'));
      await tester.pumpAndSettle();
      expect(container.read(searchSelectionProvider), isEmpty);
      expect(container.read(discoveryProvider).interests.moodSelected, isFalse);
      expect(container.read(searchDraftProvider).origin, '小樽駅');
      expect(
        container.read(settingsProvider).requireValue.profile.walking,
        Walking.plenty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
