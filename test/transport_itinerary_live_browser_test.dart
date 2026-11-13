@TestOn('browser')
library;

// Browser test plugin registration only; production imports cloud_functions.
// ignore: depend_on_referenced_packages
import 'package:cloud_functions_web/cloud_functions_web.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:http/http.dart' as http;
import 'package:sightseeing_matching_app/firebase_options.dart';
import 'package:sightseeing_matching_app/service/transport/transport_itinerary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'one real FlutterFire Callable → Dify → Flutter request',
    () async {
      FirebaseCoreWeb.registerWith(webPluginRegistrar);
      FirebaseAuthWeb.registerWith(webPluginRegistrar);
      FirebaseFunctionsWeb.registerWith(webPluginRegistrar);
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
      final auth = FirebaseAuth.instance;
      await auth.setPersistence(Persistence.NONE);
      // Explicit isolated smoke-test authentication only. The production service never signs in.
      final user = (await auth.signInAnonymously()).user!;
      try {
        final file = await http.get(
          Uri.parse(const String.fromEnvironment('TRANSPORT_NETWORK_URL')),
        );
        expect(file.statusCode, 200);
        var calls = 0;
        final service = TransportItineraryService(
          isAuthenticated: () async => auth.currentUser != null,
          invoke: (data) async {
            calls++;
            return TransportItineraryService.callFirebase(data);
          },
        );
        final result = await service.optimize(file.body);
        expect(calls, 1);
        expect(result.itinerary.status, 'feasible');
        expect(result.itinerary.visits, isNotEmpty);
        expect(result.itinerary.legs, isNotEmpty);
        expect(result.itinerary.toJson().containsKey('requiresReview'), isTrue);
        // Log only a success marker, never UID, tokens, entire network or itinerary.
        // Detailed schema is asserted by unit tests; actual optional fields are preserved in data.
      } finally {
        await user.delete();
        await auth.signOut();
      }
    },
    skip: !const bool.fromEnvironment('TRANSPORT_LIVE_TEST'),
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
