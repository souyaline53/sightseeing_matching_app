import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../data/catalog_data.dart';
import '../service/photo_source.dart';

/// Keep decoded images alive for the session. Swiping never resolves a URL.
final experiencePhotosProvider = FutureProvider<Map<String, ImageInfo?>>((
  ref,
) async {
  final snapshot = ref.watch(catalogProvider);
  if (!snapshot.hasValue) await ref.watch(catalogProvider.future);
  if (!ref.mounted) return {};
  final catalog = ref.read(catalogProvider).requireValue;
  final images = <String, ImageInfo?>{};
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    for (final image in images.values) {
      image?.dispose();
    }
  });
  await Future.wait(
    catalog.experiences.map((experience) async {
      final image = await _loadPhoto(experience.photo);
      if (disposed) {
        image?.dispose();
      } else {
        images[experience.id] = image;
      }
    }),
  );
  return images;
});

Future<ImageInfo?> _loadPhoto(String url) async {
  final stream = photoSource(url).resolve(ImageConfiguration.empty);
  final completer = Completer<ImageInfo?>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) {
      if (!completer.isCompleted) {
        completer.complete(image);
      } else {
        image.dispose();
      }
    },
    onError: (Object error, StackTrace? stack) {
      if (!completer.isCompleted) completer.complete(null);
    },
  );
  stream.addListener(listener);
  try {
    return await completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => null,
    );
  } finally {
    stream.removeListener(listener);
  }
}
