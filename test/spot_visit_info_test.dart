import 'package:sightseeing_matching_app/model/catalog_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/model/spot_visit_info.dart';
import 'package:sightseeing_matching_app/screen/admin/spot_visit_info_form.dart';

Map<String, dynamic> scheduled() => {
  'openingHoursStatus': 'scheduled',
  'openingHours': {
    for (final day in spotWeekdays.keys)
      day: day == 'mon'
          ? []
          : [
              {'open': '09:00', 'close': '12:00'},
              {'open': '13:00', 'close': '17:00'},
            ],
  },
};
void main() {
  test('legacy defaults are unknown, nullable fees and independent drafts', () {
    final source = {
      'admissionFee': {'note': 'keep', 'custom': true},
    };
    final info = SpotVisitInfo.fromMap(source)..validate();
    expect(info.data['openingHours'], null);
    expect(info.data['reservationRequired'], null);
    expect(info.data['admissionFee']['adultYen'], null);
    expect(
      evaluateSpotVisit(info, DateTime.utc(2026)),
      SpotVisitStatus.unknown,
    );
    info.data['admissionFee']['note'] = 'changed';
    expect(source['admissionFee']!['note'], 'keep');
    expect(info.toMap()['admissionFee']['custom'], true);
    for (final status in feeStatusOptions.keys) {
      final fee = SpotVisitInfo.fromMap({
        'admissionFee': {'status': status},
      })..validate();
      expect(fee.data['admissionFee']['adultYen'], null);
      expect(fee.data['admissionFee']['status'], status);
    }
  });
  test('multiple hours, closed weekdays, Tokyo arrival and duration', () {
    final info = SpotVisitInfo.fromMap(scheduled())..validate();
    expect(
      evaluateSpotVisit(info, DateTime.utc(2026, 11, 17, 0)),
      SpotVisitStatus.open,
    );
    expect(
      evaluateSpotVisit(info, DateTime.utc(2026, 11, 17, 3)),
      SpotVisitStatus.closed,
    );
    expect(
      evaluateSpotVisit(
        info,
        DateTime.utc(2026, 11, 17, 7),
        durationMinutes: 61,
      ),
      SpotVisitStatus.closed,
    );
    expect(
      evaluateSpotVisit(
        info,
        DateTime.utc(2026, 11, 17, 7),
        durationMinutes: 60,
      ),
      SpotVisitStatus.open,
    );
    expect(
      evaluateSpotVisit(info, DateTime.utc(2026, 11, 15, 23)),
      SpotVisitStatus.closed,
    ); // Monday in Tokyo
  });
  test('strict times, overlap, reversed, overnight and invalid values', () {
    for (final rows in [
      [
        {'open': '9:00', 'close': '17:00'},
      ],
      [
        {'open': '09:60', 'close': '17:00'},
      ],
      [
        {'open': '22:00', 'close': '02:00'},
      ],
      [
        {'open': '12:00', 'close': '12:00'},
      ],
      [
        {'open': '09:00', 'close': '12:00'},
        {'open': '11:00', 'close': '14:00'},
      ],
    ]) {
      expect(() => validateSpotHours(rows), throwsFormatException);
    }
    validateSpotHours([
      {'open': '00:00', 'close': '24:00'},
    ]);
    for (final amount in [-1, 1.5, '800']) {
      expect(
        () => SpotVisitInfo.fromMap({
          'admissionFee': {'adultYen': amount},
        }).validate(),
        throwsFormatException,
      );
    }
    for (final url in [
      'http://example.com',
      'https://',
      'https://exa mple.com',
      'https://user:pass@example.com',
    ]) {
      expect(
        () => SpotVisitInfo.fromMap({'officialUrl': url}).validate(),
        throwsFormatException,
      );
    }
  });
  test('special closure, exceptional opening and duplicate dates', () {
    final info = SpotVisitInfo.fromMap({
      ...scheduled(),
      'specialHours': [
        {'date': '2026-11-17', 'closed': true, 'hours': [], 'note': ''},
        {
          'date': '2026-11-16',
          'closed': false,
          'hours': [
            {'open': '10:00', 'close': '15:00'},
          ],
          'note': '臨時営業',
        },
      ],
    })..validate();
    expect(
      evaluateSpotVisit(info, DateTime.utc(2026, 11, 17, 1)),
      SpotVisitStatus.closed,
    );
    expect(
      evaluateSpotVisit(info, DateTime.utc(2026, 11, 16, 1)),
      SpotVisitStatus.open,
    );
    info.data['specialHours'].add(info.data['specialHours'].first);
    expect(info.validate, throwsFormatException);
    for (final date in ['2026-02-30', '2026-2-01']) {
      expect(
        () => SpotVisitInfo.fromMap({
          'specialHours': [
            {'date': date, 'closed': true, 'hours': [], 'note': ''},
          ],
        }).validate(),
        throwsFormatException,
      );
    }
  });
  test('year wrapping seasonal periods and unknown season', () {
    final info = SpotVisitInfo.fromMap({
      'openingHoursStatus': 'always_open',
      'seasonalAvailability': {
        'status': 'seasonal',
        'periods': [
          {'startMonth': 12, 'startDay': 1, 'endMonth': 3, 'endDay': 31},
          {'startMonth': 6, 'startDay': 1, 'endMonth': 6, 'endDay': 30},
        ],
      },
    })..validate();
    expect(
      evaluateSpotVisit(info, DateTime.utc(2027, 1, 2)),
      SpotVisitStatus.open,
    );
    expect(
      evaluateSpotVisit(info, DateTime.utc(2027, 6, 2)),
      SpotVisitStatus.open,
    );
    expect(
      evaluateSpotVisit(info, DateTime.utc(2027, 4, 2)),
      SpotVisitStatus.closed,
    );
    info.data['seasonalAvailability']['periods'][0]['startDay'] = 32;
    expect(info.validate, throwsFormatException);
    expect(
      evaluateSpotVisit(
        SpotVisitInfo.fromMap({'openingHoursStatus': 'always_open'}),
        DateTime.utc(2027),
      ),
      SpotVisitStatus.open,
    );
  });
  test(
    'recursive save merge preserves nested metadata and replaces arrays',
    () {
      final merged = mergeCatalogMaps(
        {
          'photo': 'keep',
          'accessStops': ['keep'],
          'admissionFee': {'custom': true, 'adultYen': 10},
          'specialHours': [1],
        },
        {
          'admissionFee': {'adultYen': null},
          'specialHours': [],
        },
      );
      expect(merged['admissionFee'], {'custom': true, 'adultYen': null});
      expect(merged['specialHours'], isEmpty);
      expect(merged['photo'], 'keep');
      expect(merged['accessStops'], ['keep']);
    },
  );
  test('new metadata leaves card serialization unchanged', () {
    final legacy = {
      'title': '公園',
      'area': '北海道',
      'category': '自然',
      'description': '紹介',
      'story': '物語',
      'surprise': '魅力',
      'minutes': 60,
      'accessMinutes': 10,
      'order': 0,
      'photo': '',
      'photoPath': '',
      'additionalPhotos': [],
      'additionalPhotoPaths': [],
    };
    final oldCard = CatalogRecord('park', CatalogKind.sightseeing, legacy);
    final newCard = CatalogRecord('park', CatalogKind.sightseeing, {
      ...legacy,
      ...SpotVisitInfo.fromMap(scheduled()).toMap(),
    });
    expect(newCard.toExperience().toJson(), oldCard.toExperience().toJson());
    expect(newCard.visitInfo.data['openingHoursStatus'], 'scheduled');
  });
  test('visit spanning midnight respects next day special closure', () {
    final info = SpotVisitInfo.fromMap({
      'openingHoursStatus': 'always_open',
      'specialHours': [
        {'date': '2026-11-18', 'closed': true, 'hours': [], 'note': ''},
      ],
    });
    expect(
      evaluateSpotVisit(
        info,
        DateTime.utc(2026, 11, 17, 14, 30),
        durationMinutes: 60,
      ),
      SpotVisitStatus.closed,
    );
    expect(
      evaluateSpotVisit(
        info,
        DateTime.utc(2026, 11, 17, 14, 30),
        durationMinutes: 30,
      ),
      SpotVisitStatus.open,
    );
  });
  test('adjacent unsorted hours form a continuous visit window', () {
    final info = SpotVisitInfo.fromMap(scheduled());
    info.data['openingHours']['tue'] = [
      {'open': '12:00', 'close': '17:00'},
      {'open': '09:00', 'close': '12:00'},
    ];
    expect(
      evaluateSpotVisit(
        info,
        DateTime.utc(2026, 11, 17, 2),
        durationMinutes: 120,
      ),
      SpotVisitStatus.open,
    );
  });
  testWidgets(
    'weekly switches, multiple time rows and closure preserve draft',
    (tester) async {
      final draft = SpotVisitDraft(scheduled());
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Form(child: SpotVisitInfoForm(draft: draft)),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('営業時間・営業期間'));
      await tester.pumpAndSettle();
      final monday = find.widgetWithText(SwitchListTile, '月曜日：休業');
      await tester.ensureVisible(monday);
      await tester.tap(monday);
      await tester.pumpAndSettle();
      expect(draft.snapshot()['openingHours']['mon'], [
        {'open': '09:00', 'close': '17:00'},
      ]);
      final add = find.text('月曜日を追加');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      final open = find.byKey(const ValueKey('weekly-mon-1-input-open'));
      final close = find.byKey(const ValueKey('weekly-mon-1-input-close'));
      await tester.ensureVisible(open);
      await tester.enterText(open, '18:00');
      await tester.ensureVisible(close);
      await tester.enterText(close, '20:00');
      SpotVisitInfo.fromMap(draft.snapshot()).validate();
      expect(draft.snapshot()['openingHours']['mon'], hasLength(2));
      final enabled = find.widgetWithText(SwitchListTile, '月曜日：営業');
      await tester.ensureVisible(enabled);
      await tester.tap(enabled);
      await tester.pumpAndSettle();
      expect(draft.snapshot()['openingHours']['mon'], isEmpty);
    },
  );
  testWidgets(
    'legacy form draft saves defaults; edits preserve typed values and nested hours',
    (tester) async {
      final draft = SpotVisitDraft({});
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Form(child: SpotVisitInfoForm(draft: draft)),
              ),
            ),
          ),
        ),
      );
      SpotVisitInfo.fromMap(draft.snapshot()).validate();
      await tester.tap(find.text('施設情報'));
      await tester.pumpAndSettle();
      final adult = find.byKey(const ValueKey('fee-input-adultYen'));
      await tester.ensureVisible(adult);
      await tester.enterText(adult, '800');
      expect(draft.snapshot()['admissionFee']['adultYen'], 800);
      await tester.enterText(adult, '');
      expect(draft.snapshot()['admissionFee']['adultYen'], null);
      final reloaded = SpotVisitDraft({
        ...scheduled(),
        'specialHours': [
          {
            'date': '2026-12-31',
            'closed': false,
            'hours': [
              {'open': '10:00', 'close': '15:00'},
            ],
            'note': '',
          },
        ],
      });
      SpotVisitInfo.fromMap(reloaded.snapshot()).validate();
      expect(reloaded.snapshot()['openingHours'], scheduled()['openingHours']);
      expect(
        reloaded.snapshot()['specialHours'][0]['hours'][0]['open'],
        '10:00',
      );
      expect(reloaded.snapshot().toString(), isNot(contains('_formRows_')));
    },
  );
}
