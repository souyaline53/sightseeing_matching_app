import 'dart:io';
import 'package:crypto/crypto.dart';
import 'web_build_guard.dart';

Future<void> runFlutter(List<String> arguments) async {
  final process = await Process.start(
    'flutter',
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(
      'flutter',
      arguments,
      'Flutter command failed',
      code,
    );
  }
}

Future<void> main(List<String> args) async {
  try {
    await runFlutter(['pub', 'get']);
    // Flutter 3.41.6 tracks only SDK web.dart as WebEntrypointTarget input.
    // Invalidate that target when building so new plugin dependencies cannot
    // reuse an entry point from before Firebase was installed. Native caches
    // and user data are untouched; Flutter regenerates the registrant itself.
    final build = Directory('.dart_tool/flutter_build');
    if (await build.exists()) {
      await for (final entry in build.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File &&
            entry.uri.pathSegments.last == 'web_entrypoint.stamp') {
          await entry.delete();
        }
      }
    }
    await runFlutter(['build', 'web', '--release', ...args]);
    final revision = sha256
        .convert(await File('build/web/main.dart.js').readAsBytes())
        .toString()
        .substring(0, 16);
    final bootstrap = File('build/web/flutter_bootstrap.js');
    final bootstrapText = await bootstrap.readAsString();
    await bootstrap.writeAsString(
      bootstrapText.replaceAll(
        '"main.dart.js"',
        '"main.dart.js?release=$revision"',
      ),
    );
    final index = File('build/web/index.html');
    await index.writeAsString(
      (await index.readAsString()).replaceFirst(
        'src="flutter_bootstrap.js"',
        'src="flutter_bootstrap.js?release=$revision"',
      ),
    );
    verifyWebBuild(Directory.current);
    stdout.writeln('PASS: Firebase Web plugins are registered in this release');
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
