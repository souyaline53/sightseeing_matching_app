import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/web_build_guard.dart';

void main() {
  late Directory root;
  const plugins = {
    'firebase_core_web': 'FirebaseCoreWeb',
    'cloud_firestore_web': 'FirebaseFirestoreWeb',
    'firebase_auth_web': 'FirebaseAuthWeb',
    'firebase_storage_web': 'FirebaseStorageWeb',
    'cloud_functions_web': 'FirebaseFunctionsWeb',
    'shared_preferences_web': 'SharedPreferencesPlugin',
  };
  File file(String name) => File('${root.path}/$name');
  void write(String name, String content) {
    final f = file(name);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  const registrant =
      '.dart_tool/flutter_build/release/web_plugin_registrant.dart';
  setUp(() {
    root = Directory.systemTemp.createTempSync('web-build-guard-');
    write(
      '.flutter-plugins-dependencies',
      jsonEncode({
        'plugins': {
          'web': [
            for (final name in plugins.keys) {'name': name},
          ],
        },
      }),
    );
  });
  tearDown(() => root.deleteSync(recursive: true));
  test('rejects the observed stale preferences-only registrant', () {
    write(
      registrant,
      "import 'package:shared_preferences_web/shared_preferences_web.dart'; void registerPlugins(){ SharedPreferencesPlugin.registerWith(); }",
    );
    write('build/web/main.dart.js', 'existing app without Firebase SDK');
    expect(
      () => verifyWebBuild(root),
      throwsA(
        isA<StateError>().having(
          (e) => e.message.toString(),
          'missing Firebase registration',
          contains('firebase_core_web'),
        ),
      ),
    );
  });
  test(
    'registration sources alone do not prove compiled output contains the SDK',
    () {
      write(
        registrant,
        plugins.entries
            .map(
              (e) =>
                  "import 'package:${e.key}/plugin.dart'; ${e.value}.registerWith();",
            )
            .join('\n'),
      );
      write('build/web/main.dart.js', 'old compiled output');
      expect(() => verifyWebBuild(root), throwsStateError);
    },
  );
  test('accepts a complete registrant and compiled SDK initialization', () {
    write(
      registrant,
      plugins.entries
          .map(
            (e) =>
                "import 'package:${e.key}/plugin.dart'; ${e.value}.registerWith();",
          )
          .join('\n'),
    );
    write(
      'build/web/main.dart.js',
      'load("https://www.gstatic.com/firebasejs/");',
    );
    final revision = sha256
        .convert(utf8.encode(file('build/web/main.dart.js').readAsStringSync()))
        .toString()
        .substring(0, 16);
    write(
      'build/web/index.html',
      '<script src="flutter_bootstrap.js?release=$revision"></script>',
    );
    write('build/web/flutter_bootstrap.js', 'main.dart.js?release=$revision');
    expect(() => verifyWebBuild(root), returnsNormally);
  });
}
