import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/main.dart';
import 'package:sightseeing_matching_app/data/mock_data.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';

void main() {
  test(
    'recommendation broadens interests without losing or duplicating data',
    () {
      final deck = recommend('食', [0, 0]);
      expect(deck.first.category, '食');
      expect(deck[1].category, '歴史');
      expect(deck[2].category, isNot('食'));
      expect(deck.map((e) => e.id).toSet().length, experiences.length);
      expect(
        recommend('食', [1, 1]).map((e) => e.id),
        isNot(deck.map((e) => e.id)),
      );
    },
  );
  test('save order, duplicates, removal and reorder stay consistent', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final trip = container.read(tripProvider.notifier);
    trip.save(experiences[0]);
    trip.save(experiences[1]);
    trip.save(experiences[0]);
    expect(container.read(tripProvider).saved.length, 2);
    trip.reorder(0, 2);
    expect(container.read(tripProvider).stops.first.id, experiences[1].id);
    trip.removeStop(experiences[0]);
    expect(container.read(tripProvider).saved.length, 2);
    trip.addStop(experiences[0]);
    trip.toggle(experiences[0]);
    expect(container.read(tripProvider).stops.length, 1);
  });
  test('discovery state advances and resets through Riverpod', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(discoveryProvider.notifier);
    controller.selectMood(1);
    controller.startQuestions();
    controller.answer(0);
    controller.answer(1);
    final state = container.read(discoveryProvider);
    expect(state.step, 2);
    expect(state.deck.length, experiences.length);
    controller.advance();
    expect(container.read(discoveryProvider).index, 1);
    controller.reset();
    expect(container.read(discoveryProvider).step, 0);
    expect(container.read(discoveryProvider).answers, isEmpty);
    expect(container.read(discoveryProvider).mood, 1);
  });
  test('trip settings notify listeners and lists are immutable', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var updates = 0;
    container.listen(tripProvider, (_, next) => updates++);
    final controller = container.read(tripProvider.notifier);
    final date = DateTime(2026, 12, 1);
    controller.setDate(date);
    controller.setOrigin('小樽駅');
    controller.setTransport(false);
    final trip = container.read(tripProvider);
    expect(trip.date, date);
    expect(trip.origin, '小樽駅');
    expect(trip.publicTransport, false);
    expect(updates, 3);
    expect(() => trip.saved.add(experiences.first), throwsUnsupportedError);
  });
  testWidgets('mood to exploration, detail, save and itinerary demo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('この気分で、出かけよう  →'));
    await tester.tap(find.text('この気分で、出かけよう  →'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('誰もが知る、とびきりおいしいもの'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作り手や土地の物語を知りたい'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text(experiences.first.title));
    await tester.pumpAndSettle();
    expect(find.text('もう一歩、奥へ。'), findsOneWidget);
    await tester.tap(find.byTooltip('閉じる'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Dismissible), const Offset(500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旅を組み立てる'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('1. ${experiences.first.title}'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('自分で組み立てる'));
    await tester.tap(find.text('自分で組み立てる'));
    await tester.pumpAndSettle();
    expect(find.text('マイプラン'), findsOneWidget);
    expect(find.textContaining('サンプル時刻・実際の運行情報ではありません'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('AIに提案してもらう'));
    await tester.tap(find.text('AIに提案してもらう'));
    await tester.pumpAndSettle();
    expect(find.text('デモ用の旅程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
