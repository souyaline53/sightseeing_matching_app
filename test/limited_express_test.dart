import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/repository/transport_repository.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_transport_sheet.dart';

void main() {
  testWidgets('paid switch appears only with paid options and filters them', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Experience spot(String id) => Experience.fromJson({
      ...const Experience('', '', '', '', '', '', '', '', 60).toJson(),
      'id': id,
      'name': id,
      'accessStops': [
        {'stopId': id, 'walkingMinutes': 0},
      ],
    });
    TransportTrip trip(String id, String route, int departure) =>
        TransportTrip(id, {
          'routeId': route,
          'headsign': '目的地',
          'stopTimes': [
            {'stopId': 'a', 'sequence': 1, 'departureMinutes': departure},
            {'stopId': 'b', 'sequence': 2, 'arrivalMinutes': departure + 30},
          ],
        });
    Widget sheet(bool paid) => MaterialApp(
      home: Scaffold(
        body: ItineraryTransportSheet(
          scrollController: controller,
          from: spot('a'),
          to: spot('b'),
          date: null,
          selected: null,
          data: AsyncData(
            TransportData(
              [],
              [
                TransportRoute('r', {'name': '普通'}),
                if (paid)
                  TransportRoute('p', {
                    'name': '有料列車',
                    'trainType': 'limited_express',
                  }),
              ],
              [trip('local', 'r', 540), if (paid) trip('express', 'p', 600)],
              [],
              [],
            ),
          ),
          index: 0,
          segmentCount: 1,
          onPrevious: null,
          onNext: null,
          onClear: null,
          onRefresh: () {},
          onMap: () {},
          onExpand: () {},
          onSelect: (_) {},
          onHeaderDragStart: () {},
          onHeaderDragUpdate: (_) {},
          onHeaderDragEnd: (_) {},
          onHeaderDragCancel: () {},
        ),
      ),
    );
    await tester.pumpWidget(sheet(false));
    expect(find.byKey(const ValueKey('use-limited-express')), findsNothing);
    await tester.pumpWidget(sheet(true));
    expect(find.byKey(const ValueKey('use-limited-express')), findsOneWidget);
    expect(find.byKey(const ValueKey('choose-express-1-2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('use-limited-express')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('choose-express-1-2')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('transport-sheet-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byKey(const ValueKey('choose-express-1-2')), findsWidgets);
    expect(find.text('運賃未確認'), findsWidgets);
  });
}
