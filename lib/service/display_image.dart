import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const maxDisplayImageBytes = 200000;
const displayImageCacheControl = 'public,max-age=31536000,immutable';

/// 表示・アップロード用の静止画。ネイティブでは別isolateで処理する。
Future<Uint8List> createDisplayImage(Uint8List bytes) =>
    compute(encodeDisplayImage, bytes);

Uint8List encodeDisplayImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw StateError('画像を読み込めませんでした。');
  var picture = img.bakeOrientation(decoded.frames.first);
  final ratio = math.min(1.0, 1280 / math.max(picture.width, picture.height));
  if (ratio < 1) {
    picture = img.copyResize(
      picture,
      width: math.max(1, (picture.width * ratio).round()),
      height: math.max(1, (picture.height * ratio).round()),
    );
  }
  // JPEGへ変換し、透過画像は白背景にする。EXIF等の付帯情報は保存しない。
  final background = img.Image(
    width: picture.width,
    height: picture.height,
    numChannels: 3,
  );
  img.fill(background, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(background, picture);
  picture = background;
  for (var attempt = 0; attempt < 12; attempt++) {
    for (final quality in [84, 74, 64, 54, 44]) {
      final encoded = img.encodeJpg(picture, quality: quality);
      if (encoded.length <= maxDisplayImageBytes) return encoded;
    }
    picture = img.copyResize(
      picture,
      width: math.max(1, (picture.width * .75).round()),
      height: math.max(1, (picture.height * .75).round()),
    );
  }
  throw StateError('画像を200KB以下に変換できませんでした。');
}
