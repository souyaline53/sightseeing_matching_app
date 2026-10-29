import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../model/post.dart';
import 'video_resource.dart';

Future<VideoResource> openLocalVideo(Uint8List bytes, String mimeType) async {
  final directory = await getTemporaryDirectory();
  final extension = mimeType == 'video/webm'
      ? 'webm'
      : mimeType == 'video/quicktime'
      ? 'mov'
      : 'mp4';
  final file = File(
    directory.uri.resolve('${newPostId('video')}.$extension').toFilePath(),
  );
  await file.writeAsBytes(bytes, flush: true);
  final resource = VideoResource(VideoPlayerController.file(file), () async {
    if (await file.exists()) await file.delete();
  });
  try {
    await resource.controller.initialize().timeout(const Duration(seconds: 15));
    return resource;
  } catch (_) {
    await resource.dispose();
    rethrow;
  }
}
