import 'package:cloud_functions/cloud_functions.dart';

FirebaseFunctions transportFunctions() {
  final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
  const host = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
  if (host.isNotEmpty) functions.useFunctionsEmulator(host, 5001);
  return functions;
}
