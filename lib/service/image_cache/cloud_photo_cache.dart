import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../display_image.dart';
import '../image_policy.dart';
import 'cache_store.dart';
import 'cache_store_factory.dart';

class CloudPhotoCache {
  final PhotoCacheStore store;
  final Future<Uint8List> Function(String) download;
  final _pending = <String, Future<Uint8List>>{};
  final _memory = <String, Uint8List>{};
  CloudPhotoCache({
    PhotoCacheStore? store,
    Future<Uint8List> Function(String)? download,
  }) : store = store ?? createPhotoCacheStore(),
       download = download ?? downloadCloudPhoto;
  String _key(String url) => sha256.convert(utf8.encode(url)).toString();
  Future<Uint8List> load(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw StateError('写真が未設定です。');
    }
    final key = _key(url);
    if (_memory.containsKey(key)) {
      final bytes = _memory.remove(key)!;
      _memory[key] = bytes;
      return bytes;
    }
    final pending = _pending[key];
    if (pending != null) return pending;
    final future = _load(key, url);
    _pending[key] = future;
    try {
      return await future;
    } finally {
      _pending.remove(key);
    }
  }

  Future<Uint8List> _load(String key, String url) async {
    Uint8List? bytes;
    try {
      bytes = await store.read(key);
    } catch (_) {
      /* 保存領域が使えない場合も表示する。 */
    }
    if (bytes == null || bytes.isEmpty || bytes.length > maxDisplayImageBytes) {
      final original = await download(url);
      bytes = original.length <= maxDisplayImageBytes
          ? original
          : await createDisplayImage(original);
      try {
        await store.write(key, bytes);
      } catch (_) {
        /* 容量制限時はメモリキャッシュを使用する。 */
      }
    }
    _memory[key] = bytes;
    if (_memory.length > 64) _memory.remove(_memory.keys.first);
    return bytes;
  }

  Future<void> evict(String url) async {
    final key = _key(url);
    _memory.remove(key);
    try {
      await store.remove(key);
    } catch (_) {}
  }
}

Future<Uint8List> downloadCloudPhoto(String url) async {
  final client = http.Client();
  try {
    final response = await client
        .send(http.Request('GET', Uri.parse(url)))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError('画像を取得できませんでした。');
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      builder.add(chunk);
      if (builder.length >= maxImageBytes) throw StateError('画像の上限サイズを超えています。');
    }
    return builder.takeBytes();
  } finally {
    client.close();
  }
}
