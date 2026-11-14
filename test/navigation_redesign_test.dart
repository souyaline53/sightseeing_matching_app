import 'package:sightseeing_matching_app/screen/shared/experiences/places_catalog_screen.dart';

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/screen/home/home_overview.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_editor.dart';
import 'package:sightseeing_matching_app/screen/shared/experiences/widgets/experience_deck.dart';
import 'package:sightseeing_matching_app/service/ai_matching_service.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:sightseeing_matching_app/state/itinerary_setup_state.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'test_support.dart';
import 'widget_test.dart' show boot, reveal, answerQuestions, enterDetails;

Future<void> tab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  initializeCatalogTests();

  test(
    'legacy favorites migrate once, survive trip deletion and do not return after unsaving',
    () async {
      final storage = MemorySettingsStorage();
      final oldTrip = TripState(
        id: 'legacy',
        saved: [experiences[0]],
        stops: [experiences[0]],
      );
      final legacy = TripLibrary(plans: [oldTrip]).toJson()
        ..remove('savedSpots');
      storage.value = jsonEncode(legacy);
      final repo = LocalTripsRepository(storage: storage);
      final container = ProviderContainer(
        overrides: [tripsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await container.read(tripLibraryProvider.future);
      final library = container.read(tripLibraryProvider.notifier);
      expect(
        container.read(savedExperiencesProvider).single.id,
        experiences[0].id,
      );
      library.toggleExperience(experiences[0]);
      await library.flush();
      expect((await repo.load()).savedSpots, isEmpty);
      expect((await repo.load()).plans.single.stops, hasLength(1));
      library.saveExperience(experiences[1]);
      library.delete(oldTrip.id);
      await library.flush();
      final restored = await repo.load();
      expect(restored.plans, isEmpty);
      expect(restored.savedSpots.single.id, experiences[1].id);
    },
  );

  testWidgets(
    'home preview is inert; shared favorites lead to setup and only selected places enter a trip',
    (tester) async {
      final storage = MemorySettingsStorage();
      var aiCalls = 0;
      final container = await boot(
        tester,
        tripStorage: storage,
        aiService: AiMatchingService(
          invoke: (_) async {
            aiCalls++;
            return {'recommendations': []};
          },
        ),
      );
      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((d) => d.label),
        ['ホーム', 'スワイプ', '旅のしおり', '旅程作成', 'プロフィール'],
      );
      expect(find.byType(HomeOverview), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      final preview = find.byKey(ValueKey('place-card-${experiences[0].id}'));
      expect(tester.widget<InkWell>(preview).onTap, isNull);
      expect(find.byTooltip('観光地を保存'), findsNothing);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.text('もっと見る'));
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      for (final spot in experiences.take(2)) {
        await tester.tap(find.byKey(ValueKey('place-save-${spot.id}')));
        await tester.pumpAndSettle();
      }
      expect(container.read(savedExperiencesProvider), hasLength(2));
      expect(container.read(tripLibraryProvider).requireValue.plans, isEmpty);
      await tester.tap(find.byKey(ValueKey('place-card-${experiences[0].id}')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存した観光地で旅を作る'));
      await tester.pumpAndSettle();
      expect(find.byType(PlacesCatalogScreen), findsNothing);
      expect(find.byKey(const ValueKey('setup-create-manual')), findsNothing);
      final setup = container.read(itinerarySetupProvider);
      expect(setup.conditions.origin, '札幌駅');
      expect(setup.destination, '札幌駅');
      expect(setup.departureMinutes, 480);
      expect(setup.conditions.length, TripLength.day);
      expect(setup.conditions.transport, TravelMode.transit);
      expect(
        setup.conditions.resolveDate(),
        DateUtils.dateOnly(DateTime.now()),
      );
      await tester.tap(find.byKey(const ValueKey('setup-length')));
      await tester.pumpAndSettle();
      final overnight = find.widgetWithText(SimpleDialogOption, '1泊2日（対応予定）');
      expect(tester.widget<SimpleDialogOption>(overnight).onPressed, isNull);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      await tab(tester, '旅のしおり');
      expect(find.text('保存した観光地から旅を作る'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-trip-hero')), findsNothing);
      await tester.tap(find.text('保存した観光地から旅を作る'));
      await tester.pumpAndSettle();
      final selected = find.byKey(ValueKey('setup-spot-${experiences[1].id}'));
      await reveal(tester, selected);
      await tester.tap(selected);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('setup-create-manual')));
      await tester.pumpAndSettle();
      expect(find.byType(ItineraryEditor), findsOneWidget);
      expect(container.read(tripProvider).stops.single.id, experiences[1].id);
      expect(aiCalls, 0);
      await tab(tester, '旅のしおり');
      expect(find.byKey(const ValueKey('home-trip-hero')), findsOneWidget);
      await container.read(tripLibraryProvider.notifier).flush();
      await tester.pumpWidget(const SizedBox());
      await boot(tester, tripStorage: storage);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(find.byKey(const ValueKey('home-trip-hero')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'booklet Step1 starts the shared question flow and saving alone survives restart on home',
    (tester) async {
      final storage = MemorySettingsStorage();
      final container = await boot(tester, tripStorage: storage);
      await tab(tester, '旅のしおり');
      expect(find.text('Step1. 興味から旅行を作る'), findsOneWidget);
      await tester.tap(find.text('Step1. 興味から旅行を作る'));
      await tester.pumpAndSettle();
      expect(container.read(discoveryProvider).step, 2);
      expect(find.byKey(const ValueKey('mood-food')), findsOneWidget);
      container
          .read(tripLibraryProvider.notifier)
          .saveExperience(experiences[0]);
      await container.read(tripLibraryProvider.notifier).flush();
      await tester.pumpWidget(const SizedBox());
      final reopened = await boot(tester, tripStorage: storage);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(
        reopened.read(savedExperiencesProvider).single.id,
        experiences[0].id,
      );
      expect(reopened.read(tripLibraryProvider).requireValue.plans, isEmpty);
    },
  );

  testWidgets(
    'swipe supplies ten random places without AI or questions and keeps the question session intact',
    (tester) async {
      var aiCalls = 0;
      final container = await boot(
        tester,
        aiService: AiMatchingService(
          invoke: (_) async {
            aiCalls++;
            return {'recommendations': []};
          },
        ),
      );
      await tester.tap(find.text('興味から旅行を作る'));
      await tester.pumpAndSettle();
      final questionSession = container.read(discoveryProvider);
      await tab(tester, 'スワイプ');
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(ExperienceDeck)),
      );
      final deck = scope.read(discoveryProvider).deck;
      expect(deck, hasLength(10));
      expect(deck.map((e) => e.id).toSet(), hasLength(10));
      expect(find.text('今日の偶然な発見').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('体験を保存').hitTestable());
      await tester.pumpAndSettle();
      expect(container.read(savedExperiencesProvider).single.id, deck.first.id);
      expect(container.read(tripLibraryProvider).requireValue.plans, isEmpty);
      expect(container.read(discoveryProvider), same(questionSession));
      expect(aiCalls, 0);
      await tester.tap(find.text('保存した観光地で旅を作る'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('setup-spot-${deck.first.id}')),
        findsOneWidget,
      );
      await tab(tester, 'ホーム');
      expect(find.byType(HomeOverview), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new screens remain usable on a small screen with enlarged text',
    (tester) async {
      final c = await boot(tester);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await reveal(tester, find.text('もっと見る'));
      await tester.tap(find.text('もっと見る'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tab(tester, '旅のしおり');
      await reveal(tester, find.text('Step1. 興味から旅行を作る'));
      expect(find.text('Step1. 興味から旅行を作る').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tab(tester, 'スワイプ');
      expect(tester.takeException(), isNull);
      c.read(tripLibraryProvider.notifier).saveExperience(experiences.first);
      await tab(tester, '旅程作成');
      final chosen = find.byKey(ValueKey('setup-spot-${experiences.first.id}'));
      await reveal(tester, chosen);
      await tester.tap(chosen);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('setup-create-manual')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('setup-create-ai')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'eight answers yield a vertical AI list; only hearts become candidates and conditions carry over',
    (tester) async {
      final container = await boot(tester);
      final original = TripState(
        id: 'existing',
        title: '前からある旅',
        stops: [experiences[2]],
        saved: [experiences.last],
      );
      container.read(tripLibraryProvider.notifier).upsert(original);
      container
          .read(tripLibraryProvider.notifier)
          .saveExperience(experiences.last);
      await tester.tap(find.text('興味から旅行を作る'));
      await tester.pumpAndSettle();
      expect(find.text('Q1  /  8'), findsOneWidget);
      await answerQuestions(tester);
      expect(find.text('Q4 / 8'), findsOneWidget);
      await enterDetails(
        tester,
        origin: '小樽駅',
        mode: 'car',
        length: 'halfDay',
        company: 'family',
      );
      expect(find.text('Q8 / 8'), findsOneWidget);
      await tester.tap(find.text('この条件で探す'));
      await tester.pumpAndSettle();
      expect(
        container.read(tripLibraryProvider).requireValue.plans.single.toJson(),
        original.toJson(),
      );
      final deck = container.read(discoveryProvider).deck;
      expect(deck.length, inInclusiveRange(5, 10));
      expect(find.byType(PageView), findsNothing);
      expect(container.read(savedExperiencesProvider), hasLength(1));
      await tester.tap(
        find.byKey(ValueKey('recommendation-save-${deck.first.id}')),
      );
      await tester.pumpAndSettle();
      expect(container.read(savedExperiencesProvider), hasLength(2));
      await tester.tap(find.text('保存した観光地で旅を作る'));
      await tester.pumpAndSettle();
      final setup = container.read(itinerarySetupProvider);
      expect(setup.conditions.origin, '小樽駅');
      expect(setup.conditions.transport, TravelMode.car);
      expect(setup.conditions.length, TripLength.halfDay);
      expect(setup.conditions.company, Company.family);
      expect(
        setup.conditions.resolveDate(),
        DateUtils.dateOnly(DateTime.now()),
      );
      final chosen = find.byKey(ValueKey('setup-spot-${deck.first.id}'));
      await reveal(tester, chosen);
      expect(find.byKey(ValueKey('setup-spot-${deck[1].id}')), findsNothing);
      await tester.tap(chosen);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('setup-create-manual')));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider).stops.single.id, deck.first.id);
      expect(
        container.read(tripLibraryProvider).requireValue.plans,
        hasLength(2),
      );
      expect(
        container
            .read(tripLibraryProvider)
            .requireValue
            .plans
            .firstWhere((p) => p.id == original.id)
            .toJson(),
        original.toJson(),
      );
      expect(container.read(tripProvider).origin, '小樽駅');
      expect(container.read(tripProvider).conditions.transport, TravelMode.car);
      expect(tester.takeException(), isNull);
    },
  );
}
