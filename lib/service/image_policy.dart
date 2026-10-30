import 'dart:typed_data';
import 'dart:ui' as ui;

/// 5MB以上は不可。UIとStorageルールで同じ十進数の閾値を使う。
const maxImageBytes = 5000000;

String imageMime(Uint8List bytes) {
  bool starts(List<int> signature, [int offset = 0]) =>
      bytes.length >= signature.length + offset &&
      List.generate(
        signature.length,
        (i) => bytes[i + offset] == signature[i],
      ).every((v) => v);
  if (starts([0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
  if (starts([71, 73, 70, 56, 55, 97]) || starts([71, 73, 70, 56, 57, 97])) {
    return 'image/gif';
  }
  if (starts([82, 73, 70, 70]) && starts([87, 69, 66, 80], 8)) {
    return 'image/webp';
  }
  throw StateError('JPEG・PNG・WebP・GIFの画像を選択してください。動画は投稿できません。');
}

Future<String> validateImage(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length >= maxImageBytes) {
    throw StateError('画像は1枚5MB未満にしてください。5MB以上の画像は投稿できません。');
  }
  final mime = imageMime(bytes);
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 1,
      targetHeight: 1,
    );
    final frame = await codec.getNextFrame();
    frame.image.dispose();
  } catch (_) {
    throw StateError('画像を読み込めません。破損していない画像を選択してください。');
  } finally {
    codec?.dispose();
  }
  return mime;
}

String imageExtension(String mime) => switch (mime) {
  'image/png' => 'png',
  'image/webp' => 'webp',
  'image/gif' => 'gif',
  _ => 'jpg',
};
