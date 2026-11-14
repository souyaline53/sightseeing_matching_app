import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/state/settings_state.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/state/itinerary_setup_state.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot, answerQuestions, enterDetails, reveal;

void main() {
  initializeCatalogTests();
  testWidgets(
    'filters cancel without changes and apply while keeping saved cards',
    (tester) async {
      final container = await boot(tester);
      await tester.tap(find.text('興味から旅行を作る'));
      await tester.pumpAndSettle();
      await answerQuestions(tester);
      await enterDetails(tester);
      await tester.tap(find.text('この条件で探す'));
      await tester.pumpAndSettle();
      final experience = container.read(discoveryProvider).deck.first;
      container.read(tripLibraryProvider.notifier).saveExperience(experience);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('条件を変更'));
      await tester.pumpAndSettle();
      expect(find.text('SEARCH FILTER'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '札幌駅'));
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      expect(container.read(searchDraftProvider).origin, '小樽駅');
      await tester.tap(find.byTooltip('条件を変更'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '札幌駅'));
      await reveal(tester, find.widgetWithText(ChoiceChip, '公共交通'));
      await tester.tap(find.widgetWithText(ChoiceChip, '公共交通'));
      await tester.tap(find.text('この条件で検索'));
      await tester.pumpAndSettle();
      expect(find.text('SEARCH FILTER'), findsNothing);
      expect(container.read(searchDraftProvider).origin, '札幌駅');
      expect(container.read(itinerarySetupProvider).conditions.origin, '札幌駅');
      expect(
        container.read(itinerarySetupProvider).conditions.transport,
        TravelMode.transit,
      );
      expect(container.read(savedExperiencesProvider).single.id, experience.id);
      expect(
        container.read(itinerarySetupProvider).conditions.resolveDate(),
        DateUtils.dateOnly(DateTime.now()),
      );
      expect(
        container
            .read(settingsProvider)
            .requireValue
            .lastSearch!
            .conditions
            .origin,
        '札幌駅',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
