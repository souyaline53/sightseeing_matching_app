import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/model/optimized_transport_itinerary.dart';
import 'package:sightseeing_matching_app/model/transport_optimization.dart';
import 'package:sightseeing_matching_app/service/transport/transport_itinerary_service.dart';

void main() {
  final network = File(
    'docs/transport_optimizer_meroad_coal_optimized.json',
  ).readAsStringSync().trim();
  Map<String, dynamic> itinerary() => {
    'status': 'feasible',
    'candidateId': 'candidate_001',
    'summary': {
      'departureSeconds': 31920,
      'arrivalSeconds': 60000,
      'transferCount': 2,
      'walkingSeconds': 2160,
    },
    'visits': [
      {'spotId': 'melon', 'arrivalSeconds': 36420},
      {'spotId': 'coal', 'arrivalSeconds': 44700},
    ],
    'legs': [
      {
        'kind': 'transit',
        'departureSeconds': 31920,
        'arrivalSeconds': 36120,
        'steps': [
          {'tripId': 'registered-trip', 'platform': '1'},
        ],
        'unknownField': {'keep': true},
      },
    ],
    'steps': [
      {'label': '乗換'},
    ],
    'requiresReview': true,
    'reviewReasons': [
      '時刻表未確認',
      {'code': 'walk'},
    ],
    'futureField': {
      'nested': [1, true, null],
    },
  };
  test(
    'real lightweight sample sent once, entire itinerary and review/steps preserved through Riverpod',
    () async {
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          transportItineraryServiceProvider.overrideWithValue(
            TransportItineraryService(
              isAuthenticated: () async => true,
              invoke: (data) async {
                calls++;
                expect(data.keys, ['transport_data']);
                expect(data['transport_data'], network);
                expect(jsonDecode(data['transport_data'])['schemaVersion'], 1);
                return {
                  'success': true,
                  'itinerary': itinerary(),
                  'message': '旅程生成成功',
                };
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final result = await container
          .read(transportItineraryServiceProvider)
          .optimizePrepared(
            PreparedTransportOptimization.fromJson({
              'inputs': {'transport_json': network},
              'bytes': utf8.encode(network).length,
            }),
          );
      expect(calls, 1);
      expect(result.itinerary.toJson(), itinerary());
      expect(result.itinerary.visitOrder, ['melon', 'coal']);
      expect(result.itinerary.summary.arrivalSeconds, 60000);
      expect(result.itinerary.summary.departureSeconds, 31920);
      expect(result.itinerary.summary.transferCount, 2);
      expect(result.itinerary.summary.walkingSeconds, 2160);
      expect(result.itinerary.requiresReview, true);
      expect(result.itinerary.reviewReasons.length, 2);
      expect(result.itinerary.legs.single.steps.single, {
        'tripId': 'registered-trip',
        'platform': '1',
      });
      expect(result.itinerary.steps.single, {'label': '乗換'});
      expect(
        () => result.itinerary.toJson()['status'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () =>
            (result.itinerary.legs.single.data['unknownField'] as Map)['keep'] =
                false,
        throwsUnsupportedError,
      );
    },
  );
  test('unauthenticated never invokes Callable or signs in', () async {
    final service = TransportItineraryService(
      isAuthenticated: () async => false,
      invoke: (_) async => fail('must not call'),
    );
    await expectLater(
      service.optimize(network),
      throwsA(
        isA<TransportItineraryException>().having(
          (e) => e.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
  });
  test('malformed and excessive input rejected before invoke', () async {
    final service = TransportItineraryService(
      isAuthenticated: () async => true,
      invoke: (_) async => fail('must not call'),
    );
    for (final raw in [
      'bad',
      '[]',
      '{}',
      jsonEncode({'schemaVersion': 2}),
      'x' * 400000,
      'あ' * 180000,
    ]) {
      await expectLater(
        service.optimize(raw),
        throwsA(isA<TransportItineraryException>()),
      );
    }
  });
  test(
    'false success, malformed envelopes and invalid review fields fail safely',
    () async {
      final responses = [
        {
          'success': false,
          'itinerary': {'status': 'infeasible'},
          'message': 'private upstream text',
        },
        {'success': 'true'},
        {'success': true, 'message': 'ok', 'itinerary': []},
        {
          'success': true,
          'message': 'ok',
          'itinerary': {...itinerary(), 'requiresReview': 'true'},
        },
        {
          'success': true,
          'message': 'ok',
          'itinerary': {...itinerary(), 'legs': 'bad'},
        },
      ];
      for (final response in responses) {
        final service = TransportItineraryService(
          isAuthenticated: () async => true,
          invoke: (_) async => response,
        );
        await expectLater(
          service.optimize(network),
          throwsA(
            isA<TransportItineraryException>().having(
              (e) => e.message.contains('private'),
              'safe message',
              false,
            ),
          ),
        );
      }
    },
  );
  test(
    'Functions failures and timeout preserve safe error codes and never retry',
    () async {
      for (final code in [
        'unauthenticated',
        'permission-denied',
        'deadline-exceeded',
        'internal',
        'unavailable',
        'resource-exhausted',
        'failed-precondition',
      ]) {
        var calls = 0;
        final service = TransportItineraryService(
          isAuthenticated: () async => true,
          invoke: (_) async {
            calls++;
            throw FirebaseFunctionsException(
              code: code,
              message: 'secret upstream text',
              details: network,
            );
          },
        );
        await expectLater(
          service.optimize(network),
          throwsA(
            isA<TransportItineraryException>()
                .having((e) => e.code, 'code', code)
                .having(
                  (e) => e.message.contains('secret'),
                  'sanitized',
                  false,
                ),
          ),
        );
        expect(calls, 1);
      }
      final service = TransportItineraryService(
        isAuthenticated: () async => true,
        invoke: (_) async => throw TimeoutException('private'),
      );
      await expectLater(
        service.optimize(network),
        throwsA(
          isA<TransportItineraryException>().having(
            (e) => e.code,
            'code',
            'deadline-exceeded',
          ),
        ),
      );
    },
  );
  test(
    'missing review flag remains unknown; response fields are detached from original mutable data',
    () {
      final original = itinerary()..remove('requiresReview');
      final model = OptimizedTransportItinerary.fromJson(original);
      (original['futureField'] as Map)['nested'] = [];
      expect(model.requiresReview, isNull);
      expect((model.toJson()['futureField'] as Map)['nested'], [1, true, null]);
    },
  );
  test('larger-than-old-cap network is sent intact exactly once', () async {
    final p = Map<String, dynamic>.from(jsonDecode(network) as Map);
    p['auditNote'] = 'x' * 3000000;
    final large = jsonEncode(p);
    var calls = 0;
    final service = TransportItineraryService(
      isAuthenticated: () async => true,
      invoke: (input) async {
        calls++;
        expect(input['transport_data'], large);
        return {'success': true, 'message': '成功', 'itinerary': itinerary()};
      },
    );
    expect(large.length, greaterThan(399999));
    final response = await service.optimize(large);
    expect(calls, 1);
    expect(response.itinerary.status, 'feasible');
  });
  test(
    'capacity, minute, daily and Dify quotas show distinct safe messages',
    () async {
      for (final entry in <(Map<String, dynamic>, String)>[
        (
          {
            'reason': 'transport-payload-too-large',
            'bytes': 5000000,
            'maxBytes': 4000000,
            'characters': 2500000,
            'maxCharacters': 2000000,
          },
          '5.00 MB / 上限4.00 MB',
        ),
        ({'reason': 'ai-minute-limit', 'retryAfterSeconds': 42}, '約42秒'),
        (
          {
            'reason': 'ai-daily-limit',
            'limit': 10,
            'resetAt': '2026-11-14T00:00:00Z',
          },
          '本日のAI作成回数（10回）',
        ),
        ({'reason': 'dify-rate-limit'}, 'AIサービス側'),
      ]) {
        var calls = 0;
        final service = TransportItineraryService(
          isAuthenticated: () async => true,
          invoke: (_) async {
            calls++;
            throw FirebaseFunctionsException(
              code: 'resource-exhausted',
              message: 'private upstream secret',
              details: entry.$1,
            );
          },
        );
        await expectLater(
          service.optimizeTrip(tripId: 'root', requestId: 'request', input: {}),
          throwsA(
            isA<TransportItineraryException>()
                .having((e) => e.message, 'message', contains(entry.$2))
                .having(
                  (e) => e.message,
                  'safe message',
                  isNot(contains('secret')),
                ),
          ),
        );
        expect(calls, 1);
      }
    },
  );
  test('over new byte or character cap never invokes callable', () async {
    final service = TransportItineraryService(
      isAuthenticated: () async => true,
      invoke: (_) async => fail('no network'),
    );
    for (final text in ['x' * 4000001, 'あ' * 1400000]) {
      await expectLater(
        service.optimize(text),
        throwsA(
          isA<TransportItineraryException>().having(
            (e) => e.code,
            'code',
            'resource-exhausted',
          ),
        ),
      );
    }
  });
  test(
    'Dify HTTP input failure reports safe status instead of generic connectivity',
    () async {
      var calls = 0;
      final service = TransportItineraryService(
        isAuthenticated: () async => true,
        invoke: (_) async {
          calls++;
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'private upstream body',
            details: {
              'reason': 'dify-http-error',
              'httpStatus': 400,
              'difyRequestStarted': true,
            },
          );
        },
      );
      await expectLater(
        service.optimizeTrip(tripId: 'root', requestId: 'request', input: {}),
        throwsA(
          isA<TransportItineraryException>()
              .having((e) => e.message, 'status', contains('HTTP 400'))
              .having(
                (e) => e.message,
                'safe',
                isNot(contains('private upstream body')),
              ),
        ),
      );
      expect(calls, 1);
    },
  );
}
