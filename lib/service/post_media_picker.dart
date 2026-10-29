import 'dart:typed_data';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../model/post.dart';
import 'media/local_video.dart';

enum PostMediaSource { library, cameraPhoto, cameraVideo }

class PickedPostMedia {
  final PostMedia media;
  final Uint8List bytes;
  const PickedPostMedia(this.media, this.bytes);
}

abstract interface class PostMediaPicker {
  Future<List<PickedPostMedia>> pick(
    PostMediaSource source, {
    required int remaining,
  });
}

final postMediaPickerProvider = Provider<PostMediaPicker>(
  (ref) => DevicePostMediaPicker(),
);

class DevicePostMediaPicker implements PostMediaPicker {
  final ImagePicker picker;
  DevicePostMediaPicker({ImagePicker? picker})
    : picker = picker ?? ImagePicker();
  @override
  Future<List<PickedPostMedia>> pick(
    PostMediaSource source, {
    required int remaining,
  }) async {
    if (remaining <= 0) throw StateError('写真・動画は6件までです。');
    final List<XFile> files;
    switch (source) {
      case PostMediaSource.library:
        files = await picker.pickMultipleMedia(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
          limit: remaining,
          requestFullMetadata: false,
        );
      case PostMediaSource.cameraPhoto:
        final file = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
          requestFullMetadata: false,
        );
        files = file == null ? [] : [file];
      case PostMediaSource.cameraVideo:
        final file = await picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: 30),
        );
        files = file == null ? [] : [file];
    }
    if (files.length > remaining) throw StateError('写真・動画は合計6件まで選択できます。');
    final result = <PickedPostMedia>[];
    var totalBytes = 0;
    for (final file in files) {
      final length = await file.length();
      totalBytes += length;
      if (totalBytes > 40 * 1024 * 1024) {
        throw StateError('メディアは合計40MBまでです。');
      }
      if (length > 20 * 1024 * 1024) {
        throw StateError('1ファイル20MBまでです。短い動画・小さい写真を選んでください。');
      }
      final mime = _mime(file);
      final video = mime.startsWith('video/');
      if (!video && !mime.startsWith('image/')) {
        throw StateError('写真または動画を選択してください。');
      }
      final bytes = await file.readAsBytes();
      if (video) {
        final resource = await openLocalVideo(bytes, mime);
        final duration = resource.controller.value.duration;
        await resource.dispose();
        if (duration > const Duration(seconds: 30)) {
          throw StateError('動画は30秒以内にしてください。');
        }
      }
      final id = newPostId('media');
      result.add(
        PickedPostMedia(
          PostMedia(
            id: id,
            source: 'local://$id',
            mimeType: mime,
            kind: video ? PostMediaKind.video : PostMediaKind.image,
          ),
          bytes,
        ),
      );
    }
    return result;
  }

  String _mime(XFile file) {
    final provided = file.mimeType;
    if (provided != null &&
        provided.isNotEmpty &&
        provided != 'application/octet-stream') {
      return provided;
    }
    final extension = file.name.toLowerCase().split('.').last;
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' || 'heif' => 'image/heic',
      'mp4' || 'm4v' => 'video/mp4',
      'webm' => 'video/webm',
      'mov' => 'video/quicktime',
      _ => '',
    };
  }
}
