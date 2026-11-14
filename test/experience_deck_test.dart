import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/repository/settings_repository.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/screen/recommendation/experience_deck.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:sightseeing_matching_app/state/experience_photos.dart';
import 'package:sightseeing_matching_app/state/settings_state.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'test_support.dart';
import 'departure_fixtures.dart';
import 'package:sightseeing_matching_app/data/departure_places.dart';
import 'package:sightseeing_matching_app/screen/recommendation/swipe_tips_animation.dart';

class _Deck extends DiscoveryNotifier {
  @override
  DiscoveryState build() => DiscoveryState(
    step: 3,
    deck: const [
      Experience('one', '体験1', '地域', '自然', '', '', '', '', 30),
      Experience('two', '体験2', '地域', '自然', '', '', '', '', 30),
    ],
  );
}

void main() {
  testWidgets('finger loops through left, right and up', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: SwipeTipsAnimation())),
      ),
    );
    Offset finger() {
      final transform = tester.widget<Transform>(
        find.byKey(const ValueKey('swipe-hint-finger')),
      );
      return Offset(
        transform.transform.storage[12],
        transform.transform.storage[13],
      );
    }

    await tester.pump(const Duration(milliseconds: 900));
    expect(finger().dx, lessThan(12));
    await tester.pump(const Duration(milliseconds: 1800));
    expect(finger().dx, greaterThan(12));
    await tester.pump(const Duration(milliseconds: 1800));
    expect(finger().dy, lessThan(24));
    await tester.pump(const Duration(milliseconds: 1800));
    expect(finger().dx, lessThan(12));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('first visit tips persist; swipes go back, save, and finish', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = MemorySettingsStorage();
    final repository = LocalSettingsRepository(storage: storage);
    final container = ProviderContainer(
      overrides: [
        discoveryProvider.overrideWith(_Deck.new),
        departurePlacesProvider.overrideWith(
          (ref) => Stream.value(departurePlaces),
        ),
        settingsRepositoryProvider.overrideWithValue(repository),
        tripsRepositoryProvider.overrideWithValue(
          LocalTripsRepository(storage: MemorySettingsStorage()),
        ),
        experiencePhotosProvider.overrideWith((ref) async => {}),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    await container.read(tripLibraryProvider.future);
    Widget app() => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: ExperienceDeck())),
    );
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('観光地カードの楽しみ方'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect((await repository.load()).experienceTipsSeen, isTrue);
    // Remounting with persisted settings must not automatically reopen tips.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('観光地カードの楽しみ方'), findsNothing);
    await tester.tap(find.byTooltip('スワイプのヒント').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('観光地カードの楽しみ方'), findsOneWidget);
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();
    Future<void> swipe(Offset offset) async {
      final finder = find.byKey(const ValueKey('experience-pages'));
      await tester.drag(finder, offset);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await swipe(const Offset(350, 0));
    expect(container.read(discoveryProvider).index, 0);
    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('experience-pages'))),
    );
    await drag.moveBy(const Offset(-20, 0));
    await tester.pump();
    await drag.moveBy(const Offset(-100, 0));
    await tester.pump(const Duration(milliseconds: 100));
    // During the swipe, the next card stays to the right of the current one.
    expect(
      tester.getTopLeft(find.text('2 / 2')).dx,
      greaterThan(tester.getTopLeft(find.text('1 / 2')).dx),
    );
    await drag.moveBy(const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await drag.up();
    await tester.pumpAndSettle();
    await swipe(const Offset(-350, 0));
    expect(container.read(discoveryProvider).index, 1);
    await swipe(const Offset(350, 0));
    expect(container.read(discoveryProvider).index, 0);
    await swipe(const Offset(0, -600));
    expect(container.read(discoveryProvider).index, 1);
    expect(container.read(savedExperiencesProvider).single.id, 'one');
    await swipe(const Offset(-350, 0));
    expect(find.text('すべての観光地を見終わりました'), findsOneWidget);
    expect(find.text('最初のカードに戻る').hitTestable(), findsOneWidget);
    await tester.tap(find.text('最初のカードに戻る'));
    await tester.pumpAndSettle();
    expect(container.read(discoveryProvider).index, 0);
    expect(container.read(savedExperiencesProvider).single.id, 'one');
    await swipe(const Offset(-350, 0));
    await swipe(const Offset(-350, 0));
    await tester.tap(find.text('条件を変更して再検索'));
    await tester.pumpAndSettle();
    expect(find.text('検索条件'), findsOneWidget);
    expect(find.text('この条件で検索'), findsOneWidget);
    expect(
      ProviderScope.containerOf(tester.element(find.text('検索条件'))),
      same(container),
    );
    await tester.tap(find.byTooltip('閉じる'));
    await tester.pumpAndSettle();
    expect(find.text('すべての観光地を見終わりました'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'legacy settings start unseen and other settings edits preserve tips',
    () {
      final json = SavedSettings().toJson()..remove('experienceTipsSeen');
      expect(SavedSettings.fromJson(json).experienceTipsSeen, isFalse);
      final seen = SavedSettings(experienceTipsSeen: true).copyWith();
      expect(SavedSettings.fromJson(seen.toJson()).experienceTipsSeen, isTrue);
    },
  );
}
