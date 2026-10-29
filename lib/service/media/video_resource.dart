import 'package:video_player/video_player.dart';

class VideoResource {
  final VideoPlayerController controller;
  final Future<void> Function() release;
  VideoResource(this.controller, this.release);
  Future<void> dispose() async {
    await controller.dispose();
    await release();
  }
}
