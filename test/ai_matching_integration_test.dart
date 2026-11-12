import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/service/ai_matching_service.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot;

void main() {
  initializeCatalogTests();
  test(
    'service preserves order, removes duplicates, caps ten and rejects malformed results',
    () async {
      final service = AiMatchingService(
        invoke: (_) async => {
          'recommendations': [
            {'spot_id': 'b', 'reason': '先'},
            {'spot_id': 'b', 'reason': '重複'},
            for (var i = 0; i < 15; i++) {'spot_id': '$i', 'reason': '理由'},
          ],
        },
      );
      final result = await service.getRecommendations(
        interests: '自然',
        mood: '癒やし',
      );
      expect(result, hasLength(10));
      expect(result.take(3).map((e) => e.spotId), ['b', '0', '1']);
      for (final bad in [
        null,
        {},
        {
          'recommendations': [1],
        },
        {
          'recommendations': [
            {'spot_id': 'a', 'reason': 1},
          ],
        },
      ]) {
        await expectLater(
          AiMatchingService(
            invoke: (_) async => bad,
          ).getRecommendations(interests: '自然', mood: '癒やし'),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'travel context uses Tokyo dates and does not confuse travel limit with available time',
    () {
      final context = aiTravelContext(const SearchConditions(), [
        'a',
        'a',
        'b',
      ], now: DateTime.utc(2026, 11, 12, 16));
      expect(context['visitDate'], '2026-11-14');
      expect(context['savedSpotIds'], ['a', 'b']);
      expect(context['maxTravelMinutes'], 120);
      for (final absent in [
        'availableMinutes',
        'visitDateTime',
        'destination',
        'visitArea',
        'email',
        'latitude',
      ]) {
        expect(context.containsKey(absent), false);
      }
    },
  );
  testWidgets(
    'loading, safe error, retry, Dify order, reason, details and swipe save',
    (tester) async {
      var calls = 0;
      final pending = Completer<dynamic>();
      final inputs = <Map<String, dynamic>>[];
      final service = AiMatchingService(
        invoke: (input) async {
          inputs.add(input);
          if (++calls == 1) return pending.future;
          return {
            'recommendations': [
              {'spot_id': experiences[1].id, 'reason': 'Difyが選んだ最初の理由'},
              {'spot_id': experiences[0].id, 'reason': '次の理由'},
            ],
          };
        },
      );
      final container = await boot(tester, aiService: service);
      final controller = container.read(discoveryProvider.notifier);
      controller.selectMood(0);
      controller.answer(0);
      controller.answer(0);
      final first = controller.showExplore(savedSpotIds: ['existing']);
      await tester.pump();
      expect(find.text('あなたに合う体験を探しています…'), findsOneWidget);
      pending.completeError(StateError('do not expose internal detail'));
      await first;
      await tester.pumpAndSettle();
      expect(find.textContaining('do not expose'), findsNothing);
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(inputs[0]['travelContext'], inputs[1]['travelContext']);
      expect((inputs.last['travelContext'] as Map)['savedSpotIds'], [
        'existing',
      ]);
      expect(container.read(discoveryProvider).deck.map((e) => e.id), [
        experiences[1].id,
        experiences[0].id,
      ]);
      expect(find.text('Difyが選んだ最初の理由').hitTestable(), findsOneWidget);
      await tester.tap(find.text('長押し・タップで詳しく').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('こんな一面も！'), findsOneWidget);
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Dismissible).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider).saved.single.id, experiences[1].id);
    },
  );
  testWidgets(
    'newer request wins and a late response cannot restore a reset search',
    (tester) async {
      final first = Completer<dynamic>(), second = Completer<dynamic>();
      var calls = 0;
      final container = await boot(
        tester,
        aiService: AiMatchingService(
          invoke: (_) => ++calls == 1 ? first.future : second.future,
        ),
      );
      final controller = container.read(discoveryProvider.notifier);
      final old = controller.showExplore();
      final fresh = controller.showExplore();
      second.complete({
        'recommendations': [
          {'spot_id': experiences[1].id, 'reason': 'new'},
        ],
      });
      await fresh;
      expect(
        container.read(discoveryProvider).deck.single.id,
        experiences[1].id,
      );
      controller.reset();
      first.complete({
        'recommendations': [
          {'spot_id': experiences[0].id, 'reason': 'old'},
        ],
      });
      await old;
      expect(container.read(discoveryProvider).step, 0);
      expect(
        container.read(discoveryProvider).deck.single.id,
        experiences[1].id,
      );
    },
  );
}
