import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

/// Run from the project root: dart run tool/generate_app_icons.dart
void main() {
  final source = img.decodePng(
    File('assets/branding/app_icon.png').readAsBytesSync(),
  )!;
  void write(String path, int size, {bool maskable = false}) {
    final canvas = img.Image(width: size, height: size, numChannels: 3);
    final background = source.getPixel(0, 0);
    img.fill(
      canvas,
      color: img.ColorRgb8(
        background.r.toInt(),
        background.g.toInt(),
        background.b.toInt(),
      ),
    );
    // Extra space keeps the pin inside the safe circle of maskable icons.
    final inset = maskable ? (size * 0.10).round() : 0;
    final resized = img.copyResize(
      source,
      width: size - inset * 2,
      height: size - inset * 2,
      interpolation: img.Interpolation.average,
    );
    img.compositeImage(canvas, resized, dstX: inset, dstY: inset);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(canvas));
    final decoded = img.decodePng(File(path).readAsBytesSync())!;
    if (decoded.width != size ||
        decoded.height != size ||
        decoded.numChannels != 3) {
      throw StateError('Invalid icon: $path');
    }
    stdout.writeln('$path (${size}x$size, RGB)');
  }

  for (final entry in {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  }.entries) {
    write(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      entry.value,
    );
  }
  const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final catalog =
      jsonDecode(File('$ios/Contents.json').readAsStringSync())
          as Map<String, dynamic>;
  final written = <String>{};
  for (final item in catalog['images'] as List<dynamic>) {
    final filename = item['filename'] as String;
    if (!written.add(filename)) continue;
    final points = double.parse((item['size'] as String).split('x').first);
    final scale = double.parse((item['scale'] as String).replaceAll('x', ''));
    write('$ios/$filename', (points * scale).round());
  }
  write('web/favicon.png', 32);
  for (final size in [192, 512]) {
    write('web/icons/Icon-$size.png', size);
    write('web/icons/Icon-maskable-$size.png', size, maskable: true);
  }
}
