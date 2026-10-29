import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'package:video_player/video_player.dart';
import 'video_resource.dart';

Future<VideoResource> openLocalVideo(Uint8List bytes, String mimeType) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final resource = VideoResource(
    VideoPlayerController.networkUrl(Uri.parse(url)),
    () async {
      web.URL.revokeObjectURL(url);
    },
  );
  try {
    await resource.controller.initialize().timeout(const Duration(seconds: 15));
    return resource;
  } catch (_) {
    await resource.dispose();
    rethrow;
  }
}
