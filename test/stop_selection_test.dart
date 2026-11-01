import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/model/stop_selection.dart';
import 'package:sightseeing_matching_app/model/admin_transport_fields.dart';
import 'package:sightseeing_matching_app/screen/admin/stop_group_options.dart';
import 'package:sightseeing_matching_app/screen/admin/admin_fields_form.dart';
import 'package:sightseeing_matching_app/service/transport/transport_search.dart';

void main() {
  final platforms = <Json>[
    {
      'id': 'f~a1',
      'feedId': 'f',
      'name': '夕張高校',
      'stopDestinations': ['新夕張駅前'],
      'latitude': 42.981771,
      'longitude': 142.006431,
    },
    {
      'id': 'f~a2',
      'feedId': 'f',
      'name': '夕張高校',
      'stopDestinations': ['夕張市石炭博物館', 'りすた'],
      'latitude': 42.980860,
      'longitude': 142.006188,
    },
  ];
  test(
    'nearby visual groups keep distinct IDs across feeds; append deduplicates without changing walking values',
    () {
      expect(groupStopSelections(platforms).single.length, 2);
      expect(
        groupStopSelections([
          ...platforms,
          {...platforms.first, 'id': 'other~a', 'feedId': 'other'},
        ]).length,
        1,
      );
      final old = <Json>[
        {'stopId': 'f~a1', 'walkingMinutes': 8, 'isPrimary': true},
      ];
      final rows = appendAccessStopSelections(old, platforms);
      expect(rows.length, 2);
      expect(rows.first['walkingMinutes'], 8);
      expect(rows.first['isPrimary'], true);
      expect(rows.last['walkingMinutes'], isNull);
      expect(rows.last['isPrimary'], false);
      final saved = readAdminFormData(
        [accessStopsField],
        {'accessStops': rows},
      );
      validateAdminFields([accessStopsField], saved);
      expect((saved['accessStops'] as List).map((r) => r['stopId']), [
        'f~a1',
        'f~a2',
      ]);
      expect(
        () => appendAccessStopSelections(old, platforms, maxRows: 1),
        throwsFormatException,
      );
      expect(old.length, 1);
      expect(stopGroupDistanceMeters(platforms), inInclusiveRange(100, 106));
    },
  );
  test(
    'same-name groups separate distant and unknown locations without chaining',
    () {
      final rows = [
        {'id': 'a', 'name': '同名', 'latitude': 0.0, 'longitude': 0.0},
        {'id': 'b', 'name': '同名', 'latitude': 0.0036, 'longitude': 0.0},
        {'id': 'c', 'name': '同名', 'latitude': 0.0072, 'longitude': 0.0},
        {'id': 'unknown', 'name': '同名'},
        {'id': 'different', 'name': '別名', 'latitude': 0.0, 'longitude': 0.0},
      ];
      final groups = groupStopSelections(rows);
      expect(groups.map((g) => g.length).where((n) => n > 1), [2]);
      expect(groups.length, 4);
      for (final group in groups) {
        expect(stopGroupDistanceMeters(group) ?? 0, lessThanOrEqualTo(500));
      }
      expect(
        stopDistanceMeters({
          'latitude': double.nan,
          'longitude': 0,
        }, rows.first),
        isNull,
      );
    },
  );
  testWidgets(
    'select all is explicit, individual platforms can be deselected, and direction search keeps sibling choices',
    (tester) async {
      final selected = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => StopGroupOptions(
                  stops: platforms,
                  search: '新夕張',
                  multiple: true,
                  selectedIds: selected,
                  onPick: (_) {},
                  onToggle: (stops, value) => setState(() {
                    for (final s in stops) {
                      value
                          ? selected.add(s['id'] as String)
                          : selected.remove(s['id']);
                    }
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      expect(selected, isEmpty);
      await tester.tap(find.text('夕張高校（2乗り場）'));
      await tester.pumpAndSettle();
      expect(find.textContaining('夕張高校／新夕張駅前方面'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group-select-f~a1')));
      await tester.pumpAndSettle();
      expect(selected, {'f~a1', 'f~a2'});
      await tester.tap(find.byKey(const ValueKey('stop-option-f~a2')));
      await tester.pumpAndSettle();
      expect(selected, {'f~a1'});
    },
  );
  test(
    'both saved platforms allow actual outbound and inbound trips without matching by name',
    () {
      TransportTrip trip(String id, List<String> stops) => TransportTrip(id, {
        'routeId': 'r',
        'headsign': id == 'out' ? '新夕張駅前' : '夕張市石炭博物館',
        'stopTimes': [
          for (var i = 0; i < stops.length; i++)
            {
              'stopId': stops[i],
              'sequence': i,
              'arrivalMinutes': 600 + i * 10,
              'departureMinutes': 600 + i * 10,
              'pickupType': 0,
              'dropOffType': 0,
            },
        ],
      });
      final trips = [
            trip('out', ['f~a1', 'f~b1']),
            trip('in', ['f~b2', 'f~a2']),
          ],
          routes = [TransportRoute('r', {})];
      final a = appendAccessStopSelections(
        [],
        platforms,
      ).map(AccessStop.new).toList();
      final b = [
        AccessStop({'stopId': 'f~b1'}),
        AccessStop({'stopId': 'f~b2'}),
      ];
      final outward = findCandidates(
        trips: trips,
        routes: routes,
        services: [],
        from: a,
        to: b,
      );
      final inward = findCandidates(
        trips: trips,
        routes: routes,
        services: [],
        from: b,
        to: a,
      );
      expect(outward.single.trip.id, 'out');
      expect(inward.single.trip.id, 'in');
      expect(outward.single.boardingLabel('夕張高校'), '夕張高校／新夕張駅前方面');
      expect(
        findCandidates(
          trips: [
            trip('wrong', ['f~b2', 'f~a2']),
          ],
          routes: routes,
          services: [],
          from: a,
          to: b,
        ),
        isEmpty,
      );
    },
  );
}
