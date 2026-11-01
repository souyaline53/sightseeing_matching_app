import 'dart:typed_data';

abstract interface class TransportAssetStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
  Future<void> remove(String key);
}
