import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../model/post.dart';
import '../../../service/photo_source.dart';

class PostMediaView extends HookConsumerWidget {
  final PostMedia media;
  final Uint8List? previewBytes;
  const PostMediaView({super.key, required this.media, this.previewBytes});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget display(Uint8List? bytes) {
      return bytes != null
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, error, stack) => const _MediaError(),
            )
          : Image(
              image: photoSource(media.source),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, error, stack) => const _MediaError(),
            );
    }

    return display(previewBytes);
  }
}

class _MediaError extends HookConsumerWidget {
  const _MediaError();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.landscape_outlined, size: 36),
            const SizedBox(height: 8),
            Text(
              '画像を表示できませんでした',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
