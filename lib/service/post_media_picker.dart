import 'dart:typed_data';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../model/post.dart';
import 'image_policy.dart';

enum PostMediaSource { library, cameraPhoto }

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
    if (remaining <= 0) throw StateError('画像は6枚までです。');
    final List<XFile> files;
    if (source == PostMediaSource.library) {
      // 圧縮で上限を回避せず、選択された元ファイルのサイズを検査する。
      files = await picker.pickMultiImage(
        limit: remaining > 1 ? remaining : null,
        requestFullMetadata: false,
      );
    } else {
      final file = await picker.pickImage(
        source: ImageSource.camera,
        requestFullMetadata: false,
      );
      files = file == null ? [] : [file];
    }
    if (files.length > remaining) throw StateError('画像は合計6枚まで選択できます。');
    final result = <PickedPostMedia>[];
    for (final file in files) {
      if (await file.length() >= maxImageBytes) {
        throw StateError('画像は1枚5MB未満にしてください。5MB以上の画像は投稿できません。');
      }
      final bytes = await file.readAsBytes();
      final mime = await validateImage(bytes);
      final id = newPostId('image');
      result.add(
        PickedPostMedia(PostMedia(id: id, source: '', mimeType: mime), bytes),
      );
    }
    return result;
  }
}
