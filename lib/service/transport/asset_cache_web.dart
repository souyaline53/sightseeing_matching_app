import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'asset_cache_store.dart';

TransportAssetStore createTransportAssetStore() => BrowserTransportAssetStore();

class BrowserTransportAssetStore implements TransportAssetStore {
  Future<web.Cache> cache() =>
      web.window.caches.open('tabisaki-transport-v2').toDart;
  String url(String key) =>
      '${web.window.location.origin}/__tabisaki_transport/$key';
  @override
  Future<Uint8List?> read(String key) async {
    final r = await (await cache()).match(url(key).toJS).toDart;
    return r == null
        ? null
        : (await r.arrayBuffer().toDart).toDart.asUint8List();
  }

  @override
  Future<void> remove(String key) async {
    await (await cache()).delete(url(key).toJS).toDart;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (bytes.length > 512 * 1024) return;
    final c = await cache();
    await c
        .put(
          url(key).toJS,
          web.Response(
            bytes.toJS,
            web.ResponseInit(
              headers: web.Headers()
                ..set('Content-Type', 'application/octet-stream'),
            ),
          ),
        )
        .toDart;
    final keys = (await c.keys().toDart).toDart;
    for (final old in keys.take(keys.length > 128 ? keys.length - 128 : 0)) {
      await c.delete(old).toDart;
    }
  }
}
