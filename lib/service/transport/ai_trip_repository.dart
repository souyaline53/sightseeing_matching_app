import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/transport.dart';
import '../../model/trip_plan.dart';
import '../cloud/cloud_services.dart';
import 'transport_admin_api.dart';

final aiTripRepositoryProvider = Provider(
  (ref) => AiTripRepository(() => ref.read(cloudServicesProvider.future)),
);

class AiTripRepository {
  final Future<CloudServices> Function() cloud;
  AiTripRepository(this.cloud);
  Future<CloudServices> authenticated() async {
    final services = await cloud();
    if (services.auth.currentUser == null) {
      throw StateError('ログインしてからAIをご利用ください。');
    }
    return services;
  }

  Future<Json> call(String name, Json input) async {
    await authenticated();
    final response = await transportFunctions()
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 130)),
        )
        .call<dynamic>(input);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Json> register(TripState trip) => call('registerAiTrip', {
    'trip': trip.toJson(),
    if (trip.ai['rootId'] != null) 'rootId': trip.ai['rootId'],
  });
  Future<DocumentReference<Json>> reference(String rootId) async {
    final s = await authenticated();
    return s.firestore
        .collection('users')
        .doc(s.auth.currentUser!.uid)
        .collection('ai_trips')
        .doc(rootId);
  }

  Json decode(Json data) => {
    ...data,
    for (final key in ['currentTrip', 'aiResult'])
      if (data[key] is String) key: jsonDecode(data[key] as String),
  };
  Future<Json?> read(String rootId) async =>
      decode((await (await reference(rootId)).get()).data() ?? {});
  Stream<Json> watch(String rootId) async* {
    yield* (await reference(
      rootId,
    )).snapshots().map((s) => decode(s.data() ?? {}));
  }

  Future<void> save(TripState trip) async {
    final root = trip.ai['rootId'];
    if (root is String) {
      await (await reference(
        root,
      )).update({'currentTrip': jsonEncode(trip.toJson())});
    }
  }

  Future<List<Json>> saved() async {
    final s = await authenticated();
    final docs = await s.firestore
        .collection('users')
        .doc(s.auth.currentUser!.uid)
        .collection('ai_trips')
        .get();
    return docs.docs.map((d) => {...decode(d.data()), 'rootId': d.id}).toList();
  }
}
