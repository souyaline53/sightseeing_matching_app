import '../model/trip_plan.dart';
import '../model/experience.dart';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/transport.dart';
import '../model/transport_journey.dart';
import '../service/cloud/cloud_services.dart';
import '../service/transport/transport_admin_api.dart';

// Explicit calls only. No full-network client downloads or real-time listeners.
final journeySearchProvider =
    Provider<Future<JourneySearchResult> Function(Json)>(
      (ref) => (query) async {
        await ref.read(cloudServicesProvider.future);
        final result = await transportFunctions()
            .httpsCallable(
              'searchTransportJourneys',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 70),
              ),
            )
            .call<Json>(query);
        return JourneySearchResult(Map<String, dynamic>.from(result.data));
      },
    );

String itineraryJourneyKey(TripState trip, Experience? from, Experience? to) {
  final date = trip.date;
  return jsonEncode({
    'date':
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    'departureSeconds': trip.departureMinutes * 60,
    'maxTransfers': 3,
    'minimumTransferSeconds': 180,
    'timetable': true,
    'from':
        from?.accessStops
            .map(
              (s) => {'stopId': s.stopId, 'walkingMinutes': s.walkingMinutes},
            )
            .toList() ??
        [],
    'to':
        to?.accessStops
            .map(
              (s) => {'stopId': s.stopId, 'walkingMinutes': s.walkingMinutes},
            )
            .toList() ??
        [],
  });
}

// The key excludes the preceding selected trip. Selecting a vehicle only filters cached results.
final itineraryJourneysProvider =
    FutureProvider.family<JourneySearchResult, String>((ref, key) async {
      final query = Map<String, dynamic>.from(jsonDecode(key) as Map);
      return ref.watch(journeySearchProvider)(query);
    });
