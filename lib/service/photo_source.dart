import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'image_cache/cloud_photo_cache.dart';

final cloudPhotoCache = CloudPhotoCache();
ImageProvider<Object> photoSource(String source) => CachedCloudPhoto(source);

class CachedCloudPhoto extends ImageProvider<CachedCloudPhoto> {
  final String url;
  const CachedCloudPhoto(this.url);
  @override
  Future<CachedCloudPhoto> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    CachedCloudPhoto key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);
  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final bytes = await cloudPhotoCache.load(url);
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      await cloudPhotoCache.evict(url);
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CachedCloudPhoto && other.url == url;
  @override
  int get hashCode => url.hashCode;
}
