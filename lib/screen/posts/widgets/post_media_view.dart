import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../model/post.dart';
import '../../../service/media/local_video.dart';
import '../../../service/media/video_resource.dart';
import '../../../service/photo_source.dart';
import '../../../state/posts_state.dart';
import '../../../state/app_tab.dart';

final playingPostVideoProvider = NotifierProvider<PlayingPostVideo, String?>(
  PlayingPostVideo.new,
);

class PlayingPostVideo extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

class PostMediaView extends HookConsumerWidget {
  final PostMedia media;
  final Uint8List? previewBytes;
  final bool active;
  const PostMediaView({
    super.key,
    required this.media,
    this.previewBytes,
    this.active = true,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget display(Uint8List? bytes) {
      if (media.kind == PostMediaKind.video) {
        if (bytes == null) return const _MediaError(message: '動画を読み込めませんでした');
        return _PostVideo(media: media, bytes: bytes, active: active);
      }
      return bytes != null
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, error, stack) => const _MediaError(),
            )
          : media.isLocal
          ? const _MediaError()
          : Image(
              image: photoSource(media.source),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, error, stack) => const _MediaError(),
            );
    }

    if (previewBytes != null || !media.isLocal) return display(previewBytes);
    return ref
        .watch(postMediaBytesProvider(media.id))
        .when(
          data: display,
          error: (_, stack) => const _MediaError(),
          loading: () => const Center(child: CircularProgressIndicator()),
        );
  }
}

class _MediaError extends HookConsumerWidget {
  final String message;
  const _MediaError({this.message = '画像を表示できませんでした'});
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
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PostVideo extends HookConsumerWidget {
  final PostMedia media;
  final Uint8List bytes;
  final bool active;
  const _PostVideo({
    required this.media,
    required this.bytes,
    required this.active,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = useMemoized(() => openLocalVideo(bytes, media.mimeType), [
      media.id,
    ]);
    final snapshot = useFuture(future);
    useEffect(() {
      var disposed = false;
      VideoResource? resource;
      future.then((value) {
        if (disposed) {
          unawaited(value.dispose());
        } else {
          resource = value;
        }
      }, onError: (Object error, StackTrace stack) {});
      return () {
        disposed = true;
        final value = resource;
        if (value != null) unawaited(value.dispose());
      };
    }, [future]);
    if (snapshot.hasError) {
      return const _MediaError(message: 'この動画形式は再生できません。MP4・WebMなどをお試しください。');
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    return _VideoControls(
      controller: snapshot.data!.controller,
      mediaId: media.id,
      active: active,
    );
  }
}

class _VideoControls extends HookConsumerWidget {
  final VideoPlayerController controller;
  final String mediaId;
  final bool active;
  const _VideoControls({
    required this.controller,
    required this.mediaId,
    required this.active,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useListenable(controller);
    final playingId = ref.watch(playingPostVideoProvider);
    final tab = ref.watch(appTabProvider);
    useEffect(() {
      if (!active || playingId != mediaId) unawaited(controller.pause());
      return null;
    }, [active, playingId]);
    useEffect(() {
      unawaited(controller.pause());
      return null;
    }, [tab]);
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
          IconButton.filledTonal(
            tooltip: controller.value.isPlaying ? '動画を一時停止' : '動画を再生',
            onPressed: () {
              if (controller.value.isPlaying) {
                controller.pause();
              } else {
                ref.read(playingPostVideoProvider.notifier).select(mediaId);
                controller.play();
              }
            },
            icon: Icon(
              controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              size: 30,
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: VideoProgressIndicator(controller, allowScrubbing: true),
          ),
        ],
      ),
    );
  }
}
