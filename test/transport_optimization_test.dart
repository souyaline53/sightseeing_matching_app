import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/transport.dart';
import 'package:sightseeing_matching_app/model/transport_optimization.dart';
import 'package:sightseeing_matching_app/service/transport/transport_optimizer_service.dart';

void main() {
  test(
    'independent preparation serializes distinct endpoints, overnight and unknown hours',
    () async {
      final origin = OptimizationPlace(
        id: 'start',
        name: '出発',
        accessStops: [
          AccessStop({'stopId': 'a', 'walkingMinutes': null}),
        ],
      );
      const end = OptimizationPlace(id: 'end', name: '到着');
      final input = TransportOptimizationInput(
        date: '2026-11-13',
        origin: origin,
        destination: end,
        departureSeconds: 82800,
        deadlineSeconds: 90000,
        visits: [
          const OptimizationVisit(
            place: OptimizationPlace(id: 'spot', name: '観光地'),
            staySeconds: 600,
          ),
        ],
      );
      final service = TransportOptimizerService((q) async {
        expect(q['destination']['id'], 'end');
        expect(q['origin']['accessStops'][0]['walkingMinutes'], isNull);
        expect(q['deadlineSeconds'], 90000);
        expect(q['visits'][0]['opening'], {'status': 'unknown', 'windows': []});
        final json = jsonEncode(q);
        return {
          'inputs': {'transport_json': json},
          'bytes': utf8.encode(json).length,
        };
      });
      final prepared = await service.build(input);
      expect(jsonDecode(prepared.transportJson)['date'], '2026-11-13');
      expect(prepared.bytes, utf8.encode(prepared.transportJson).length);
    },
  );
  test('infeasible is explicit and selected candidate must exist', () {
    expect(
      TransportOptimizationResult.fromJson({
        'status': 'infeasible',
        'candidates': [],
      }).status,
      'infeasible',
    );
    expect(
      () => TransportOptimizationResult.fromJson({
        'status': 'feasible',
        'candidates': [
          {'id': 'a'},
        ],
        'selectedCandidateId': 'b',
      }),
      throwsFormatException,
    );
    expect(
      TransportOptimizationResult.fromJson({
        'status': 'feasible',
        'candidates': [
          {'id': 'a'},
        ],
        'selectedCandidateId': 'a',
      }).selectedCandidateId,
      'a',
    );
  });
}
