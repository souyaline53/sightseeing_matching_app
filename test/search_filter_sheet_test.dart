import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/state/settings_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot, answerQuestions, enterDetails, reveal;

void main() {
  initializeCatalogTests();
  testWidgets(
    'filters cancel without changes and apply while keeping saved cards',
    (tester) async {
      final container = await boot(tester);
      await tester.tap(find.text('新しい旅を探す'));
      await tester.pumpAndSettle();
      await answerQuestions(tester);
      await enterDetails(tester);
      await tester.tap(find.text('この条件で探す'));
      await tester.pumpAndSettle();
      final experience = container.read(discoveryProvider).deck.first;
      container.read(tripProvider.notifier).save(experience);
      await tester.pumpAndSettle();
      await tester.tap(find.text('条件を変更'));
      await tester.pumpAndSettle();
      expect(find.text('SEARCH FILTER'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '札幌駅'));
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      expect(container.read(searchDraftProvider).origin, '小樽駅');
      await tester.tap(find.text('条件を変更'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '札幌駅'));
      await reveal(tester, find.widgetWithText(ChoiceChip, '公共交通'));
      await tester.tap(find.widgetWithText(ChoiceChip, '公共交通'));
      await tester.tap(find.text('この条件で検索'));
      await tester.pumpAndSettle();
      expect(find.text('SEARCH FILTER'), findsNothing);
      expect(container.read(searchDraftProvider).origin, '札幌駅');
      expect(container.read(tripProvider).origin, '札幌駅');
      expect(
        container.read(tripProvider).conditions.transport,
        TravelMode.transit,
      );
      expect(container.read(tripProvider).saved.single.id, experience.id);
      expect(
        container.read(tripProvider).travelDate,
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
