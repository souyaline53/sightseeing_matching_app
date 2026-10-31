import 'package:sightseeing_matching_app/screen/itinerary/itinerary_map.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_spot_card.dart';
import 'dart:ui' show PointerDeviceKind;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sightseeing_matching_app/widgets/departure_map.dart'
    show mapTilesEnabledProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/travel_catalog.dart';
import 'package:sightseeing_matching_app/model/trip_plan.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/repository/transport_repository.dart';
import 'package:sightseeing_matching_app/repository/trips_repository.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_editor.dart';
import 'package:sightseeing_matching_app/state/experience_photos.dart';
import 'package:sightseeing_matching_app/state/trip_library_state.dart';
import 'package:sightseeing_matching_app/state/trip_state.dart';
import 'test_support.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets('map, sheet, timetable, save and reorder at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture =
          jsonDecode(File('docs/transport/sample.json').readAsStringSync())
              as Map<String, dynamic>;
      List<T> records<T>(
        String key,
        T Function(String, Map<String, dynamic>) create,
      ) => (fixture[key] as Map<String, dynamic>).entries
          .map((e) => create(e.key, Map<String, dynamic>.from(e.value as Map)))
          .toList();
      final data = TransportData(
        records('transport_stops', TransportStop.new),
        records('transport_routes', TransportRoute.new),
        records('transport_trips', TransportTrip.new),
        records('transport_services', TransportService.new),
        [],
      );
      Experience spot(String id, String key) => Experience.fromJson({
        ...const Experience('', '', '', '', '', '', '', '', 60).toJson(),
        'id': id,
        'title': '架空体験$id',
        'accessStops': fixture['exampleSpotAccess'][key],
      });
      final spots = [spot('A', 'from'), spot('B', 'to')];
      final repo = LocalTripsRepository(storage: MemorySettingsStorage());
      await repo.save(
        TripLibrary(
          plans: [TripState(stops: spots, saved: spots)],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          catalogProvider.overrideWith(
            (ref) => Stream.value(TravelCatalog(experiences: spots)),
          ),
          tripsRepositoryProvider.overrideWithValue(repo),
          transportDataProvider.overrideWith((ref, key) async => data),
          mapTilesEnabledProvider.overrideWithValue(false),
          experiencePhotosProvider.overrideWith((ref) async => {}),
        ],
      );
      addTearDown(container.dispose);
      await container.read(tripLibraryProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: const ItineraryEditor()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('日程未定：時刻表は参考情報です'), findsOneWidget);
      final list = find.byType(ListView).last;
      expect(find.byKey(const ValueKey('itinerary-map')), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.byType(MarkerLayer), findsNothing);
      final select = find.byKey(const ValueKey('choose-sample_trip_0-2-3'));
      await tester.scrollUntilVisible(
        select,
        160,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      await Scrollable.ensureVisible(tester.element(select), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(select);
      await tester.pumpAndSettle();
      expect(
        container
            .read(tripProvider)
            .transportSelections
            .single
            .data['boardingStopId'],
        'sample_b',
      );
      expect(
        container
            .read(tripProvider)
            .transportSelections
            .single
            .data['walkingMinutesBefore'],
        isNull,
      );
      final timetable = find.text('時刻表・アクセスを見る').first;
      await Scrollable.ensureVisible(tester.element(timetable), alignment: .5);
      await tester.tap(timetable);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('途中駅・バス停の時刻表'),
        140,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNWidgets(2));
      expect(find.textContaining('架空停留所A'), findsOneWidget);
      expect(find.text('08:32'), findsOneWidget);
      await tester.tap(find.byTooltip('時刻表を閉じる'));
      await tester.pumpAndSettle();
      final other = find.byKey(const ValueKey('choose-sample_trip_1-2-3'));
      await tester.scrollUntilVisible(
        other,
        160,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      await Scrollable.ensureVisible(tester.element(other), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(other);
      await tester.pumpAndSettle();
      expect(
        container
            .read(tripProvider)
            .transportSelections
            .single
            .data['selectedTripId'],
        'sample_trip_1',
      );
      await tester.tap(find.byKey(const ValueKey('itinerary-save')));
      await tester.pumpAndSettle();
      expect(
        (await repo.load())
            .activeTrip!
            .transportSelections
            .single
            .data['selectedTripId'],
        'sample_trip_1',
      );
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
      expect(container.read(tripProvider).transportSelections, isEmpty);
      final beforeDrag = container.read(tripProvider).stops.first.id;
      final drag = await tester.startGesture(
        kind: size.width > 320
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch,
        tester.getCenter(find.byType(ReorderableDragStartListener).first),
      );
      await tester.pump();
      for (var step = 0; step < 11; step++) {
        await drag.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(container.read(tripProvider).stops.first.id, isNot(beforeDrag));
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
          .clearSnackBars();
      await tester.pumpAndSettle();
      final sheet = tester.widget<DraggableScrollableSheet>(
        find.byType(DraggableScrollableSheet),
      );
      sheet.controller!.jumpTo(1);
      await tester.pumpAndSettle();
      final mapButton = find.byKey(const ValueKey('itinerary-show-map'));
      await tester.scrollUntilVisible(
        mapButton,
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('transport-sheet-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(mapButton);
      await tester.pumpAndSettle();
      await tester.tap(mapButton);
      await tester.pumpAndSettle();
      expect(sheet.controller!.size, closeTo(sheet.minChildSize, .01));
      expect(find.text('開く'), findsNothing);
      expect(sheet.snapSizes, [sheet.minChildSize, 1]);
      final header = find.byKey(const ValueKey('transport-sheet-header'));
      final pointerKind = size.width > 320
          ? PointerDeviceKind.mouse
          : PointerDeviceKind.touch;
      Future<void> slowHeaderSwipe(double dy, {bool cancel = false}) async {
        final gesture = await tester.startGesture(
          tester.getCenter(header),
          kind: pointerKind,
        );
        await tester.pump();
        await gesture.moveBy(Offset(0, dy.sign * 20));
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.moveBy(Offset(0, dy - dy.sign * 20));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 200));
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
      }

      await slowHeaderSwipe(-70);
      await tester.pumpAndSettle();
      expect(sheet.controller!.size, closeTo(1, .01));
      await tester.drag(
        find.text('交通情報'),
        const Offset(0, 90),
        kind: size.width > 320
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      expect(sheet.controller!.size, closeTo(sheet.minChildSize, .001));
      await slowHeaderSwipe(-70);
      expect(sheet.controller!.size, closeTo(1, .001));
      // The fixed header remains draggable after the timetable has been scrolled.
      await tester.scrollUntilVisible(
        mapButton,
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('transport-sheet-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(header).top,
        closeTo(tester.getRect(find.byType(ItineraryMap)).top, .1),
      );
      await slowHeaderSwipe(65);
      expect(sheet.controller!.size, closeTo(sheet.minChildSize, .001));
      await slowHeaderSwipe(-70);
      await slowHeaderSwipe(45, cancel: true);
      final afterCancel = sheet.controller!.size;
      expect(
        (afterCancel - sheet.minChildSize).abs() < .001 ||
            (afterCancel - 1).abs() < .001,
        isTrue,
      );
      // Scrolling the content must also settle at one of the same two endpoints.
      sheet.controller!.jumpTo(1);
      await tester.pumpAndSettle();
      final bodyScrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('transport-sheet-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      bodyScrollable.position.jumpTo(0);
      await tester.drag(
        find.byKey(const ValueKey('transport-sheet-scroll')),
        const Offset(0, 90),
        kind: pointerKind,
      );
      await tester.pumpAndSettle();
      final afterBodyDrag = sheet.controller!.size;
      expect(
        (afterBodyDrag - sheet.minChildSize).abs() < .001 ||
            (afterBodyDrag - 1).abs() < .001,
        isTrue,
      );
      await tester.tap(find.byTooltip('タイトルを編集'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '週末の小さな旅');
      await tester.tap(find.text('変更'));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(container.read(tripProvider).title, '週末の小さな旅');
      expect(tester.takeException(), isNull);
    });
  }
}
