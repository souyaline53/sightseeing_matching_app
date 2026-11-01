import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'gtfs_txt_file.dart';

Future<List<GtfsTxtFile>?> pickGtfsTxtFiles() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.txt,text/plain'
    ..multiple = true;
  final result = Completer<List<GtfsTxtFile>?>();
  input.oncancel = ((web.Event e) {
    if (!result.isCompleted) result.complete(null);
  }).toJS;
  Future<void> read() async {
    final selected = input.files;
    if (selected == null || selected.length == 0) {
      result.complete(null);
      return;
    }
    if (selected.length > 100) throw StateError('txt一式は100ファイル以内にしてください');
    final names = <String>{};
    var total = 0;
    for (var i = 0; i < selected.length; i++) {
      final f = selected.item(i)!;
      total += f.size;
      if (!RegExp(r'^[a-z][a-z0-9_]*\.txt$').hasMatch(f.name)) {
        throw StateError('${f.name}：画面の一覧を参照して標準ファイル名に変更してください');
      }
      if (!names.add(f.name)) throw StateError('${f.name}が重複しています');
      if (f.size == 0 ||
          f.size > 50 * 1024 * 1024 ||
          total > 100 * 1024 * 1024) {
        throw StateError('空でないtxtを選択してください。1ファイル50MiB・合計100MiBまで');
      }
    }
    final files = <GtfsTxtFile>[];
    for (var i = 0; i < selected.length; i++) {
      final f = selected.item(i)!;
      files.add(
        GtfsTxtFile(
          f.name,
          (await f.arrayBuffer().toDart).toDart.asUint8List(),
        ),
      );
    }
    result.complete(files);
  }

  input.onchange = ((web.Event e) {
    read().catchError((Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    });
  }).toJS;
  input.click();
  return result.future;
}
