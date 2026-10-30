import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'cache_store.dart';

PhotoCacheStore createPhotoCacheStore() => BrowserPhotoCacheStore();

class BrowserPhotoCacheStore implements PhotoCacheStore {
  final String name;
  BrowserPhotoCacheStore({this.name = 'tabisaki-display-images-v1'});
  Future<web.Cache> _cache() => web.window.caches.open(name).toDart;
  String _url(String key) =>
      '${web.window.location.origin}/__tabisaki_photo_cache_v1/$key';
  @override
  Future<Uint8List?> read(String key) async {
    final response = await (await _cache()).match(_url(key).toJS).toDart;
    if (response == null) return null;
    return (await response.arrayBuffer().toDart).toDart.asUint8List();
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final cache = await _cache();
    await cache
        .put(
          _url(key).toJS,
          web.Response(
            bytes.toJS,
            web.ResponseInit(
              headers: web.Headers()
                ..set('Content-Type', 'application/octet-stream'),
            ),
          ),
        )
        .toDart;
    final keys = (await cache.keys().toDart).toDart;
    for (final old in keys.take(keys.length > 320 ? keys.length - 320 : 0)) {
      await cache.delete(old).toDart;
    }
  }

  @override
  Future<void> remove(String key) async {
    await (await _cache()).delete(_url(key).toJS).toDart;
  }
}
