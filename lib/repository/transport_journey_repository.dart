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

// The key excludes the preceding selected trip. Selecting a vehicle only filters cached results.
final itineraryJourneysProvider =
    FutureProvider.family<JourneySearchResult, String>((ref, key) async {
      final query = Map<String, dynamic>.from(jsonDecode(key) as Map);
      return ref.watch(journeySearchProvider)(query);
    });
