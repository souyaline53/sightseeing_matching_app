import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<Uint8List?> pickGtfsZip() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.zip,application/zip';
  final result = Completer<Uint8List?>();
  input.oncancel = ((web.Event e) {
    if (!result.isCompleted) result.complete(null);
  }).toJS;
  input.onchange = ((web.Event e) {
    final file = input.files?.item(0);
    if (file == null) {
      result.complete(null);
      return;
    }
    if (file.size > 20971520) {
      result.completeError(StateError('ZIPは20MiB以内にしてください'));
      return;
    }
    file.arrayBuffer().toDart.then(
      (buffer) => result.complete(buffer.toDart.asUint8List()),
      onError: (Object e) => result.completeError(e),
    );
  }).toJS;
  input.click();
  return result.future;
}
