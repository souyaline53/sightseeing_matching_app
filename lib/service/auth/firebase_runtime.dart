import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_options.dart';

class FirebaseRuntime {
  final bool available;
  final String? message;
  const FirebaseRuntime.ready() : available = true, message = null;
  const FirebaseRuntime.unavailable(this.message) : available = false;
}

Future<FirebaseRuntime> initializeAccountFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 12));
    }
    const emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
    if (emulatorHost.isNotEmpty) {
      await FirebaseAuth.instance.useAuthEmulator(
        emulatorHost,
        const int.fromEnvironment(
          'FIREBASE_AUTH_EMULATOR_PORT',
          defaultValue: 9099,
        ),
      );
      FirebaseFirestore.instance.useFirestoreEmulator(
        emulatorHost,
        const int.fromEnvironment(
          'FIRESTORE_EMULATOR_PORT',
          defaultValue: 8080,
        ),
      );
    }
    return const FirebaseRuntime.ready();
  } catch (_) {
    return const FirebaseRuntime.unavailable(
      'アカウント機能に接続できません。Firebase設定を確認してください。ゲストとして引き続き利用できます。',
    );
  }
}
