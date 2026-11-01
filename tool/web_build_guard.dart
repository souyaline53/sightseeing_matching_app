import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Checks the generated entry point AND the compiled output; HTTP 200 alone
/// cannot detect a release whose Firebase Web plugins were tree-shaken away.
void verifyWebBuild(Directory root) {
  File file(String path) => File('${root.path}/$path');
  final plugins = file('.flutter-plugins-dependencies');
  if (!plugins.existsSync()) throw StateError('先にflutter pub getを実行してください');
  final metadata = jsonDecode(plugins.readAsStringSync()) as Map;
  final expected = ((metadata['plugins'] as Map)['web'] as List)
      .map((p) => (p as Map)['name'] as String)
      .toSet();
  final build = Directory('${root.path}/.dart_tool/flutter_build');
  final registrants = build.existsSync()
      ? build
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where(
              (f) => f.uri.pathSegments.last == 'web_plugin_registrant.dart',
            )
            .toList()
      : <File>[];
  if (registrants.isEmpty) {
    throw StateError(
      'Webプラグイン登録ファイルがありません。dart run tool/build_web.dartで再ビルドしてください',
    );
  }
  registrants.sort(
    (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
  );
  final source = registrants.first.readAsStringSync();
  final missing = expected
      .where((name) => !source.contains('package:$name/'))
      .toList();
  for (final registration in [
    'FirebaseCoreWeb.registerWith',
    'FirebaseFirestoreWeb.registerWith',
    'FirebaseAuthWeb.registerWith',
    'FirebaseStorageWeb.registerWith',
    'FirebaseFunctionsWeb.registerWith',
  ]) {
    if (!source.contains(registration)) missing.add(registration);
  }
  if (missing.isNotEmpty) {
    throw StateError(
      'Webビルドのプラグイン登録が古いか不足しています: ${missing.join(', ')}。dart run tool/build_web.dartで再ビルドしてください',
    );
  }
  final js = file('build/web/main.dart.js');
  if (!js.existsSync() || !js.readAsStringSync().contains('firebasejs/')) {
    throw StateError(
      '配信用JavaScriptにFirebase Web SDKの初期化が含まれていません。dart run tool/build_web.dartで再ビルドしてください',
    );
  }
  final revision = sha256
      .convert(js.readAsBytesSync())
      .toString()
      .substring(0, 16);
  final index = file('build/web/index.html'),
      bootstrap = file('build/web/flutter_bootstrap.js');
  if (!index.existsSync() ||
      !bootstrap.existsSync() ||
      !index.readAsStringSync().contains(
        'flutter_bootstrap.js?release=$revision',
      ) ||
      !bootstrap.readAsStringSync().contains(
        'main.dart.js?release=$revision',
      )) {
    throw StateError(
      'Web起動ファイルとJavaScriptの版が一致しません。dart run tool/build_web.dartで再ビルドしてください',
    );
  }
}

void main(List<String> args) {
  try {
    verifyWebBuild(Directory.current);
    stdout.writeln(
      'PASS: Web plugin registration and compiled Firebase SDK initialization',
    );
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
