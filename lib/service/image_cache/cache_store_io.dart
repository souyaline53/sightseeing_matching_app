import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'cache_store.dart';

PhotoCacheStore createPhotoCacheStore() => FilePhotoCacheStore();

class FilePhotoCacheStore implements PhotoCacheStore {
  final Future<Directory> Function() directory;
  FilePhotoCacheStore({Future<Directory> Function()? directory})
    : directory =
          directory ??
          (() async => Directory(
            '${(await getApplicationCacheDirectory()).path}/tabisaki-display-images-v1',
          ));
  Future<File> _file(String key) async =>
      File('${(await directory()).path}/$key.jpg');
  @override
  Future<Uint8List?> read(String key) async {
    final file = await _file(key);
    if (!await file.exists()) return null;
    await file.setLastModified(DateTime.now());
    return file.readAsBytes();
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final folder = await directory();
    await folder.create(recursive: true);
    final file = await _file(key);
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
    final files = await folder
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.jpg'))
        .cast<File>()
        .toList();
    if (files.length <= 320) return;
    final modified = {
      for (final entry in files) entry: await entry.lastModified(),
    };
    files.sort((a, b) => modified[a]!.compareTo(modified[b]!));
    for (final entry in files.take(files.length - 320)) {
      await entry.delete();
    }
  }

  @override
  Future<void> remove(String key) async {
    final file = await _file(key);
    if (await file.exists()) await file.delete();
  }
}
