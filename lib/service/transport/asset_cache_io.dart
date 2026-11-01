import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'asset_cache_store.dart';

TransportAssetStore createTransportAssetStore() => FileTransportAssetStore();

class FileTransportAssetStore implements TransportAssetStore {
  final Future<Directory> Function() directory;
  FileTransportAssetStore({Future<Directory> Function()? directory})
    : directory =
          directory ??
          (() => getApplicationCacheDirectory().then(
            (d) => Directory('${d.path}/tabisaki-transport-v2'),
          ));
  Future<File> file(String key) async =>
      File('${(await directory()).path}/$key.bin');
  @override
  Future<Uint8List?> read(String key) async {
    final f = await file(key);
    if (!await f.exists()) return null;
    await f.setLastModified(DateTime.now());
    return f.readAsBytes();
  }

  @override
  Future<void> remove(String key) async {
    final f = await file(key);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (bytes.length > 512 * 1024) return;
    final dir = await directory();
    await dir.create(recursive: true);
    final f = await file(key),
        temp = File('${f.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(f.path);
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.bin'))
        .cast<File>()
        .toList();
    if (files.length > 128) {
      final times = {for (final f in files) f: await f.lastModified()};
      files.sort((a, b) => times[a]!.compareTo(times[b]!));
      for (final f in files.take(files.length - 128)) {
        await f.delete();
      }
    }
  }
}
