import 'package:sightseeing_matching_app/service/ai_matching_service.dart';
import 'departure_fixtures.dart';
import 'package:sightseeing_matching_app/data/departure_places.dart';
import 'package:sightseeing_matching_app/service/address_geocoder.dart';
import 'package:sightseeing_matching_app/screen/itinerary/widgets/itinerary_spot_card.dart';
import 'package:sightseeing_matching_app/service/cloud/cloud_services.dart';
import 'package:sightseeing_matching_app/service/cloud/catalog_admin_service.dart';
import 'package:sightseeing_matching_app/repository/firestore_catalog_repository.dart';
import 'package:sightseeing_matching_app/repository/cloud_image_repository.dart';
import 'package:sightseeing_matching_app/widgets/departure_map.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/main.dart';
import 'package:sightseeing_matching_app/model/search_settings.dart';
import 'package:sightseeing_matching_app/repository/chat_repository.dart';
import 'package:sightseeing_matching_app/state/chat_state.dart';
import 'package:sightseeing_matching_app/repository/settings_repository.dart';
import 'package:sightseeing_matching_app/state/settings_state.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'package:sightseeing_matching_app/state/experience_photos.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'package:sightseeing_matching_app/state/itinerary_setup_state.dart';
import 'package:sightseeing_matching_app/screen/shared/experiences/widgets/experience_deck.dart';
import 'package:sightseeing_matching_app/service/curiosity_questions.dart';
import 'test_support.dart';
import 'package:sightseeing_matching_app/state/account_state.dart';
import 'package:sightseeing_matching_app/repository/account_repository.dart';
import 'package:sightseeing_matching_app/repository/posts_repository.dart';
import 'package:sightseeing_matching_app/state/posts_state.dart';
import 'package:sightseeing_matching_app/service/post_media_picker.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/screen/profile/profile_setting_screen.dart';

Future<void> reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(finder), alignment: .2);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> boot(
  WidgetTester tester, {
  MemorySettingsStorage? storage,
  MemorySettingsStorage? tripStorage,
  PostsRepository? postsRepository,
  PostMediaPicker? mediaPicker,
  AccountRepository? accountRepository,
  ChatRepository? chatRepository,
  CloudServices? cloudServices,
  FirestoreCatalogRepository? adminRepository,
  Object? catalogFailure,
  AddressGeocoder? geocoder,
  List<DeparturePlace>? departures,
  Future<Map<String, ImageInfo?>> Function()? photos,
  AiMatchingService? aiService,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // General flow tests use a returning visitor; first-visit tips have their own test.
  final settingsStorage = storage ?? MemorySettingsStorage();
  if (!settingsStorage.failRead && !settingsStorage.failWrite) {
    final repository = LocalSettingsRepository(storage: settingsStorage);
    await repository.save(
      (await repository.load()).copyWith(experienceTipsSeen: true),
    );
  }
  final container = ProviderContainer(
    overrides: [
      aiMatchingServiceProvider.overrideWithValue(
        aiService ?? fixtureAiMatchingService(),
      ),
      departurePlacesProvider.overrideWith(
        (ref) => Stream.value(departures ?? departurePlaces),
      ),
      if (geocoder != null) addressGeocoderProvider.overrideWithValue(geocoder),
      guestIdentityRepositoryProvider.overrideWithValue(
        MemoryGuestIdentityRepository(),
      ),
      accountRepositoryProvider.overrideWith(
        (ref) => accountRepository ?? FakeAccountRepository(),
      ),
      if (chatRepository != null)
        chatRepositoryProvider.overrideWith((ref) => chatRepository),
      catalogProvider.overrideWith((ref) {
        if (catalogFailure != null) throw catalogFailure;
        return Stream.value(testCatalog);
      }),
      if (cloudServices != null)
        cloudServicesProvider.overrideWith((ref) => cloudServices),
      if (adminRepository != null)
        adminCatalogRepositoryProvider.overrideWithValue(adminRepository),
      postMediaPickerProvider.overrideWithValue(
        mediaPicker ?? MemoryImagePicker(),
      ),
      cloudImageRepositoryProvider.overrideWithValue(MemoryCloudImages()),
      postsRepositoryProvider.overrideWithValue(
        postsRepository ?? MemoryPostsRepository.seeded(),
      ),
      mapTilesEnabledProvider.overrideWithValue(false),
      tripsRepositoryProvider.overrideWithValue(
        LocalTripsRepository(storage: tripStorage ?? MemorySettingsStorage()),
      ),
      settingsRepositoryProvider.overrideWithValue(
        LocalSettingsRepository(storage: settingsStorage),
      ),
      experiencePhotosProvider.overrideWith(
        (ref) => photos?.call() ?? Future.value({}),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MyApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> answerQuestions(
  WidgetTester tester, {
  int mood = 0,
  int reason = 0,
  int broaden = 0,
}) async {
  final moodId = CuriosityQuestions.moods[mood].id;
  await reveal(tester, find.byKey(ValueKey('mood-$moodId')));
  await tester.tap(find.byKey(ValueKey('mood-$moodId')));
  await tester.pumpAndSettle();
  await reveal(
    tester,
    find.text(CuriosityQuestions.reason(mood).choices[reason]),
  );
  await tester.tap(find.text(CuriosityQuestions.reason(mood).choices[reason]));
  await tester.pumpAndSettle();
  await reveal(
    tester,
    find.text(CuriosityQuestions.broaden(mood, reason).choices[broaden]),
  );
  await tester.tap(
    find.text(CuriosityQuestions.broaden(mood, reason).choices[broaden]),
  );
  await tester.pumpAndSettle();
}

Future<void> chooseDepartureDate(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(CalendarDatePicker),
      matching: find.text('${DateTime.now().day}'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> enterDetails(
  WidgetTester tester, {
  String origin = '小樽駅',
  String mode = 'car',
  String length = 'day',
  String company = 'solo',
}) async {
  await tester.tap(find.byKey(ValueKey('origin-chip-$origin')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('travel-$mode')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('length-$length')));
  await tester.pumpAndSettle();
  await chooseDepartureDate(tester);
  await tester.tap(find.byKey(ValueKey('company-$company')));
  await tester.pumpAndSettle();
}

void main() {
  initializeCatalogTests();
  testWidgets(
    'questions precede conditions; execution, cards and itinerary remain connected',
    (tester) async {
      final container = await boot(tester);
      expect(find.text('前回の条件で探す'), findsNothing);
      await tester.tap(find.text('興味から旅行を作る'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mood-food')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mood-food')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('地元の人だけが知る、隠れた名物'));
      await tester.pumpAndSettle();
      expect(find.text('その街にもう一つ秘密があるとしたら？'), findsOneWidget);
      await tester.tap(find.byTooltip('前の画面へ'));
      await tester.pumpAndSettle();
      expect(container.read(discoveryProvider).answers, [1]);
      await tester.tap(find.text('一度は食べたい、とびきり贅沢な一品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('土地の光を手仕事に探す'));
      await tester.pumpAndSettle();
      expect(find.text('どこから旅を始める？'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(container.read(settingsProvider).requireValue.lastSearch, isNull);
      await enterDetails(tester, length: 'day');
      await tester.pumpAndSettle();
      await tester.tap(find.text('この条件で探す'));
      await tester.pumpAndSettle();
      final last = container.read(settingsProvider).requireValue.lastSearch!;
      expect(last.conditions.origin, '小樽駅');
      expect(last.conditions.transport, TravelMode.car);
      expect(last.conditions.length, TripLength.day);
      expect(last.searchedAt.isUtc, isTrue);
      expect(
        container.read(itinerarySetupProvider).conditions.resolveDate(),
        DateUtils.dateOnly(DateTime.now()),
      );
      final initial = container.read(discoveryProvider).deck;
      expect(container.read(savedExperiencesProvider), isEmpty);
      await tester.tap(
        find.byKey(ValueKey('recommendation-save-${initial[0].id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('recommended-place-${initial[1].id}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('こんな一面も！'), findsOneWidget);
      await reveal(tester, find.text('この体験を保存'));
      await tester.tap(find.text('この体験を保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      expect(container.read(tripLibraryProvider).requireValue.plans, isEmpty);
      await tester.tap(find.text('保存した観光地で旅を作る'));
      await tester.pumpAndSettle();
      for (final spot in initial.take(2)) {
        final checkbox = find.byKey(ValueKey('setup-spot-${spot.id}'));
        await reveal(tester, checkbox);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('setup-create-manual')));
      await tester.pumpAndSettle();
      final date = DateUtils.dateOnly(DateTime.now());
      expect(
        find.textContaining('${date.year}/${date.month}/${date.day}（'),
        findsOneWidget,
      );
      expect(find.byType(CalendarDatePicker), findsNothing);
      final before = container.read(tripProvider).stops.first.id;
      await tester.tap(
        find
            .descendant(
              of: find.byType(ItinerarySpotCard),
              matching: find.byType(PopupMenuButton<String>),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider).stops.first.id, isNot(before));
      expect(find.textContaining('時刻表は参考情報です'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('itinerary-view-booklet')));
      await tester.pumpAndSettle();
      expect(find.text('マイプラン'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('旅程作成'));
      await tester.pumpAndSettle();
      expect(container.read(tripProvider).stops.length, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'profile and preset management remain independent of the search flow',
    (tester) async {
      final storage = MemorySettingsStorage();
      final container = await boot(tester, storage: storage);
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ProfileSettingTile).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '旭川駅');
      await tester.tap(find.text('保存する'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ホーム'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('興味から旅行を作る'));
      await tester.pumpAndSettle();
      await answerQuestions(tester);
      expect(container.read(searchDraftProvider).origin, '旭川駅');
      await enterDetails(tester);
      await tester.tap(find.text('条件を保存して検索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '小樽の休日');
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      await container
          .read(settingsProvider.notifier)
          .savePreset(const SearchConditions(origin: '千歳駅'), 'もう一つ');
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('名前の変更').first);
      await tester.tap(find.text('名前の変更').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '名前を変更');
      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      final card = find.ancestor(
        of: find.text('名前を変更'),
        matching: find.byType(Card),
      );
      await reveal(
        tester,
        find.descendant(of: card, matching: find.text('内容の編集')),
      );
      await tester.tap(find.descendant(of: card, matching: find.text('内容の編集')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '江別駅');
      await reveal(tester, find.text('上書き保存'));
      await tester.tap(find.text('上書き保存'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('名前を変更'));
      await tester.tap(find.descendant(of: card, matching: find.text('読み込み')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mood-food')), findsOneWidget);
      await answerQuestions(tester);
      expect(container.read(searchDraftProvider).origin, '江別駅');
      expect(
        container.read(settingsProvider).requireValue.profile.origin,
        '旭川駅',
      );
      expect(
        container
            .read(settingsProvider)
            .requireValue
            .lastSearch!
            .conditions
            .origin,
        '小樽駅',
      );
      await tester.tap(find.text('プロフィール'));
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.descendant(of: card, matching: find.text('削除')),
      );
      await tester.tap(find.descendant(of: card, matching: find.text('削除')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).requireValue.presets.length, 2);
      await tester.tap(find.descendant(of: card, matching: find.text('削除')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '削除'));
      await tester.pumpAndSettle();
      expect(
        (await LocalSettingsRepository(storage: storage).load()).presets.length,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'empty home omits search history and new searches use profile defaults',
    (tester) async {
      final storage = MemorySettingsStorage();
      await LocalSettingsRepository(storage: storage).save(
        SavedSettings(
          profile: const UserProfile(origin: '旭川駅'),
          lastSearch: LastSearch(
            conditions: SearchConditions(
              origin: '函館駅',
              dateChoice: DateChoice.fixed,
              fixedDate: DateTime(2020),
            ),
            searchedAt: DateTime(2020),
          ),
        ),
      );
      final container = await boot(tester, storage: storage);
      expect(find.text('前回の条件で探す'), findsNothing);
      await tester.tap(find.text('興味から旅行を作る'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mood-food')), findsOneWidget);
      await answerQuestions(tester);
      expect(container.read(searchDraftProvider).origin, '旭川駅');
      expect(
        container
            .read(settingsProvider)
            .requireValue
            .lastSearch!
            .conditions
            .origin,
        '函館駅',
      );
      expect(find.byType(CalendarDatePicker), findsNothing);
      await tester.tap(find.byKey(const ValueKey('origin-chip-札幌駅')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('travel-transit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('length-day')));
      await tester.pumpAndSettle();
      await chooseDepartureDate(tester);
      await tester.tap(find.byKey(const ValueKey('company-solo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この条件で探す'));
      await tester.pumpAndSettle();
      expect(container.read(discoveryProvider).step, 3);
      expect(
        container.read(itinerarySetupProvider).conditions.resolveDate(),
        DateUtils.dateOnly(DateTime.now()),
      );
      container.read(discoveryProvider.notifier).reset();
      await tester.pumpAndSettle();
      await tester.tap(find.text('興味から旅行を作る'));
      await tester.pumpAndSettle();
      await answerQuestions(tester);
      expect(container.read(searchDraftProvider).origin, '旭川駅');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('all four moods and question branches remain intact', (
    tester,
  ) async {
    final container = await boot(tester);
    await tester.binding.setSurfaceSize(const Size(360, 640));
    final flow = container.read(discoveryProvider.notifier);
    for (var i = 0; i < 4; i++) {
      flow.startQuestions();
      await tester.pumpAndSettle();
      final key = ValueKey('mood-${CuriosityQuestions.moods[i].id}');
      await reveal(tester, find.byKey(key));
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(find.text(CuriosityQuestions.reason(i).title), findsOneWidget);
      await tester.tap(find.text(CuriosityQuestions.reason(i).choices.first));
      await tester.pumpAndSettle();
      expect(find.text(CuriosityQuestions.broaden(i, 0).title), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('photos are prepared once; only upward swipes save', (
    tester,
  ) async {
    final ready = Completer<Map<String, ImageInfo?>>();
    var loads = 0;
    final container = await boot(
      tester,
      photos: () {
        loads++;
        return ready.future;
      },
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('スワイプ'),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    ready.complete({});
    await tester.pumpAndSettle();
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(ExperienceDeck)),
    );
    await tester.drag(
      find.byKey(const ValueKey('experience-pages')),
      const Offset(-350, 0),
    );
    await tester.pumpAndSettle();
    expect(scope.read(discoveryProvider).index, 1);
    await tester.drag(
      find.byKey(const ValueKey('experience-pages')),
      const Offset(350, 0),
    );
    await tester.pumpAndSettle();
    expect(scope.read(discoveryProvider).index, 0);
    expect(container.read(savedExperiencesProvider), isEmpty);
    final experience = scope.read(discoveryProvider).deck.first;
    await tester.drag(
      find.byKey(const ValueKey('experience-pages')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(container.read(savedExperiencesProvider).map((e) => e.id), [
      experience.id,
    ]);
    expect(container.read(tripLibraryProvider).requireValue.plans, isEmpty);
    expect(loads, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('load and save failures keep profile data and editable input', (
    tester,
  ) async {
    final storage = MemorySettingsStorage()..failRead = true;
    await boot(tester, storage: storage);
    expect(find.text('再読み込み'), findsOneWidget);
    storage.failRead = false;
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('プロフィール'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ProfileSettingTile).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '入力は残す');
    storage.failWrite = true;
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存できませんでした'), findsOneWidget);
    storage.failWrite = false;
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();
    expect(
      (await LocalSettingsRepository(storage: storage).load()).profile.origin,
      '入力は残す',
    );
    expect(tester.takeException(), isNull);
  });
}
