import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/model/admin_transport_fields.dart';
import 'package:sightseeing_matching_app/screen/admin/admin_fields_form.dart';
import 'package:sightseeing_matching_app/screen/admin/transport_edit_dialog.dart';

void main() {
  final fixture =
      jsonDecode(File('docs/transport/sample.json').readAsStringSync())
          as Map<String, dynamic>;
  test('date/time and persisted values have strict types and ranges', () {
    expect(validAdminDate('2026-02-30'), false);
    expect(validAdminDate('2028-02-29'), true);
    expect(parseAdminTime('25:10'), 1510);
    expect(parseAdminTime('08:60'), null);
    for (final bad in ['10', -1, 1.5, true]) {
      expect(
        () => validateTransport('transport_fares', {
          'routeId': 'r',
          'fromStopId': 'a',
          'toStopId': 'b',
          'amountYen': bad,
          'fareType': 'adult',
        }),
        throwsFormatException,
      );
    }
    expect(
      () => validateAdminFields(accessStopFields, {
        'stopId': 'a',
        'walkingMinutes': null,
        'isPrimary': true,
      }),
      returnsNormally,
    );
    expect(
      () => validateAdminFields(accessStopFields, {
        'stopId': 'a',
        'walkingMinutes': '8',
      }),
      throwsFormatException,
    );
    expect(
      () => validateAdminFields(accessStopFields, {
        'stopId': 'a',
        'isPrimary': 'true',
      }),
      throwsFormatException,
    );
    expect(
      () => validateTransport('transport_agencies', {
        'name': 123,
        'timezone': 'Asia/Tokyo',
      }),
      throwsFormatException,
    );
  });
  test(
    'calendar types, reversed times, duplicate sequence and sample fixtures',
    () {
      for (final c in fixture.keys.where((c) => c.startsWith('transport_'))) {
        for (final raw in (fixture[c] as Map).values) {
          expect(
            () => validateTransport(c, Map<String, dynamic>.from(raw as Map)),
            returnsNormally,
          );
        }
      }
      final service = Map<String, dynamic>.from(
        (fixture['transport_services'] as Map).values.first as Map,
      );
      expect(
        () => validateTransport('transport_services', {
          ...service,
          'weekdays': ['1'],
        }),
        throwsFormatException,
      );
      expect(
        () => validateTransport('transport_services', {
          ...service,
          'validTo': '2026-02-30',
        }),
        throwsFormatException,
      );
      final trip = Map<String, dynamic>.from(
        (fixture['transport_trips'] as Map).values.first as Map,
      );
      final times = (trip['stopTimes'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      times[1]['sequence'] = 1;
      expect(
        () =>
            validateTransport('transport_trips', {...trip, 'stopTimes': times}),
        throwsFormatException,
      );
    },
  );
  Future<void> boot(
    WidgetTester tester,
    String collection, {
    Map<String, dynamic>? record,
    bool duplicate = false,
    required Future<void> Function(String, Map<String, dynamic>) save,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminReferenceOptionsProvider.overrideWith((ref, key) async => []),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => TransportEditDialog(
                    collection: collection,
                    title: '編集',
                    record: record,
                    duplicate: duplicate,
                    onSave: save,
                  ),
                ),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
  }

  for (final collection in fixture.keys.where(
    (c) => c.startsWith('transport_'),
  )) {
    testWidgets(
      '$collection uses typed fields and preserves unknown metadata',
      (tester) async {
        final entry = (fixture[collection] as Map).entries.first;
        Map<String, dynamic>? saved;
        await boot(
          tester,
          collection,
          record: {
            ...Map<String, dynamic>.from(entry.value as Map),
            'id': entry.key,
            'customMetadata': {'keep': true},
          },
          save: (id, data) async {
            saved = data;
          },
        );
        expect(find.textContaining('JSON'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('transport-save')));
        await tester.pumpAndSettle();
        expect(saved, isNotNull);
        expect(saved!['customMetadata'], {'keep': true});
        expect(saved!.keys.any((k) => k.startsWith('_formRows_')), false);
        validateTransport(collection, saved!);
      },
    );
  }
  testWidgets('integer paste filtering, scalar row edits and duplicate ID', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    String? savedId;
    await boot(
      tester,
      'transport_stops',
      record: {
        'id': 'old',
        'name': '駅',
        'type': 'bus_stop',
        'routeIds': ['r'],
      },
      duplicate: true,
      save: (id, data) async {
        savedId = id;
        saved = data;
      },
    );
    final id = find.byKey(const ValueKey('transport-id'));
    expect(tester.widget<TextFormField>(id).controller!.text, isEmpty);
    await tester.enterText(id, 'new_id');
    final route = find.byKey(const ValueKey('routeIds-0-input-value'));
    await Scrollable.ensureVisible(tester.element(route), alignment: .5);
    await tester.pumpAndSettle();
    await tester.enterText(route, 'changed');
    await tester.tap(find.byKey(const ValueKey('transport-save')));
    await tester.pumpAndSettle();
    expect(savedId, 'new_id');
    expect(saved!['routeIds'], ['changed']);
  });
  testWidgets('walking unknown stays null; digits only and typed bool', (
    tester,
  ) async {
    final data = prepareAdminData(
      [accessStopsField],
      {
        'accessStops': [
          {'stopId': 'a', 'walkingMinutes': null, 'isPrimary': true},
        ],
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminReferenceOptionsProvider.overrideWith((ref, key) async => []),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                child: AdminFieldsForm(
                  fields: const [accessStopsField],
                  data: data,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      (readAdminFormData([accessStopsField], data)['accessStops'] as List)
          .first['walkingMinutes'],
      null,
    );
    final walking = find.byKey(
      const ValueKey('accessStops-0-input-walkingMinutes'),
    );
    await tester.enterText(walking, '8abc');
    final snapshot = readAdminFormData([accessStopsField], data);
    expect((snapshot['accessStops'] as List).first['walkingMinutes'], 8);
    expect((snapshot['accessStops'] as List).first['isPrimary'], true);
  });
  testWidgets('invalid URL prevents save and retry preserves text', (
    tester,
  ) async {
    int calls = 0;
    await boot(
      tester,
      'transport_agencies',
      record: {'id': 'a', 'name': '事業者', 'timezone': 'Asia/Tokyo'},
      save: (id, data) async {
        calls++;
        throw StateError('通信に失敗');
      },
    );
    final website = find.byKey(const ValueKey('input-website'));
    await tester.enterText(website, 'invalid');
    await tester.tap(find.byKey(const ValueKey('transport-save')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.enterText(website, 'https://example.com');
    await tester.tap(find.byKey(const ValueKey('transport-save')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
      tester.widget<TextFormField>(website).controller!.text,
      'https://example.com',
    );
  });
  testWidgets('invalid timetable stays editable and cannot reach save', (
    tester,
  ) async {
    var calls = 0;
    final record = Map<String, dynamic>.from(
      (fixture['transport_trips'] as Map).values.first as Map,
    );
    await boot(
      tester,
      'transport_trips',
      record: {...record, 'id': 'trip'},
      save: (id, data) async {
        calls++;
      },
    );
    final time = find.byKey(
      const ValueKey('stopTimes-0-input-departureMinutes'),
    );
    await Scrollable.ensureVisible(tester.element(time), alignment: .5);
    await tester.pumpAndSettle();
    await tester.enterText(time, '25:10');
    await tester.tap(find.byKey(const ValueKey('transport-save')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('発着時刻を停車順に並べてください（翌日は25:10等）'), findsOneWidget);
    expect(tester.widget<TextFormField>(time).controller!.text, '25:10');
    await tester.enterText(time, '08:10');
    await tester.tap(find.byKey(const ValueKey('transport-save')));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
}
