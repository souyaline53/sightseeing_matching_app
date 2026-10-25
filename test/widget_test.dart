import 'dart:async';
import 'package:sightseeing_matching_app/state/experience_photos.dart';
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
  test('deleting the last and only cards keeps the cursor valid', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(discoveryProvider.notifier);
    controller.selectMood(0);
    controller.answer(0);
    controller.answer(0);
    var deck = container.read(discoveryProvider).deck;
    controller.goTo(deck.length - 1);
    controller.removeCard(deck.last.id);
    expect(container.read(discoveryProvider).index, deck.length - 2);
    deck = container.read(discoveryProvider).deck;
    for (final e in deck) {
      controller.removeCard(e.id);
    }
    expect(container.read(discoveryProvider).deck, isEmpty);
    expect(container.read(discoveryProvider).index, 0);
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
  testWidgets(
    'all six moods fit on a small phone and open questions with one tap',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ProviderScope(child: MyApp()));
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        expect(find.byKey(ValueKey('mood-$i')).hitTestable(), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('mood-5')));
      await tester.pumpAndSettle();
      expect(find.text('どちらに惹かれる？'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('horizontal browsing, saving and deleting use prepared photos', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ready = Completer<Map<String, ImageInfo?>>();
    var loads = 0;
    final container = ProviderContainer(
      overrides: [
        experiencePhotosProvider.overrideWith((ref) {
          loads++;
          return ready.future;
        }),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(discoveryProvider.notifier);
    controller.selectMood(0);
    controller.answer(0);
    controller.answer(0);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyApp()),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    ready.complete(
      {},
    ); // Failed photos are prepared placeholders, without retrying.
    await tester.pumpAndSettle();
    expect(loads, 1);
    final initial = container.read(discoveryProvider).deck;
    final pages = find.byKey(const ValueKey('experience-pages'));
    await tester.drag(pages, const Offset(-340, 0));
    await tester.pumpAndSettle();
    expect(container.read(discoveryProvider).index, 1);
    await tester.drag(pages, const Offset(340, 0));
    await tester.pumpAndSettle();
    expect(container.read(discoveryProvider).index, 0);
    await tester.drag(
      find.byType(Dismissible).hitTestable(),
      const Offset(0, 700),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(discoveryProvider).deck.map((e) => e.id),
      isNot(contains(initial.first.id)),
    );
    expect(container.read(discoveryProvider).deck.length, initial.length - 1);
    expect(container.read(discoveryProvider).index, 0);
    expect(container.read(tripProvider).saved, isEmpty);
    await tester.drag(
      find.byType(Dismissible).hitTestable(),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(container.read(tripProvider).saved.single.id, initial[1].id);
    expect(container.read(discoveryProvider).index, 1);
    final save = find.byTooltip('体験を保存').hitTestable();
    final card = find.byType(Dismissible).hitTestable();
    expect(tester.getRect(card).contains(tester.getCenter(save)), isTrue);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(container.read(tripProvider).saved.length, 2);
    await tester.drag(pages, const Offset(340, 0));
    await tester.pumpAndSettle();
    expect(container.read(discoveryProvider).deck.first.id, initial[1].id);
    expect(loads, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('last card loops to first with horizontal and save swipes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [experiencePhotosProvider.overrideWith((ref) async => {})],
    );
    addTearDown(container.dispose);
    final discovery = container.read(discoveryProvider.notifier);
    discovery.selectMood(0);
    discovery.answer(0);
    discovery.answer(0);
    final deck = container.read(discoveryProvider).deck;
    discovery.goTo(deck.length - 1);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    final pages = find.byKey(const ValueKey('experience-pages'));
    await tester.drag(pages, const Offset(-340, 0));
    await tester.pumpAndSettle();
    expect(container.read(discoveryProvider).index, 0);
    await tester.drag(pages, const Offset(340, 0));
    await tester.pumpAndSettle();
    expect(container.read(discoveryProvider).index, deck.length - 1);
    await tester.drag(
      find.byType(Dismissible).hitTestable(),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(container.read(discoveryProvider).index, 0);
    expect(container.read(tripProvider).saved.single.id, deck.last.id);
    expect(container.read(discoveryProvider).deck.length, deck.length);
    await tester.drag(pages, const Offset(340, 0));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(Dismissible).hitTestable(),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(container.read(tripProvider).saved.length, 1);
    expect(container.read(discoveryProvider).index, 0);
    // Deleting down to a single card still permits saving and looping.
    for (final e in deck.skip(1)) {
      discovery.removeCard(e.id);
    }
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(Dismissible).hitTestable(),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(container.read(discoveryProvider).index, 0);
    expect(container.read(tripProvider).saved.length, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('mood to exploration, detail, save and itinerary demo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mood-0')));
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
    await tester.drag(
      find.byType(Dismissible).hitTestable(),
      const Offset(0, -800),
    );
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
