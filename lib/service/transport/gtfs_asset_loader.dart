import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'asset_cache_factory.dart';
import 'asset_cache_store.dart';

Object decodeTransportAsset(Map<String, dynamic> input) {
  final bytes = input['bytes'] as Uint8List;
  final raw = input['gzip'] == true ? GZipDecoder().decodeBytes(bytes) : bytes;
  if (raw.length != (input['rawBytes'] as int)) {
    throw const FormatException('交通データの展開サイズが一致しません');
  }
  return jsonDecode(utf8.decode(raw)) as Object;
}

class GtfsAssetLoader {
  final Future<Uint8List> Function(String, int) download;
  final TransportAssetStore store;
  final String namespace;
  GtfsAssetLoader(
    this.download, {
    TransportAssetStore? store,
    this.namespace = '',
  }) : store = store ?? createTransportAssetStore();
  final _memory = <String, Uint8List>{};
  final _inflight = <String, Future<Object>>{};
  int _memoryBytes = 0;
  int requests = 0, downloadedBytes = 0, cacheHits = 0;
  Future<Object> load(
    String path, {
    required String checksum,
    required int rawBytes,
    bool gzip = true,
  }) {
    final key = sha256
        .convert(utf8.encode('$namespace/$path/$checksum'))
        .toString();
    return _inflight.putIfAbsent(
      key,
      () => _load(key, path, checksum, rawBytes, gzip).whenComplete(() {
        _inflight.remove(key);
      }),
    );
  }

  Future<Object> _load(
    String key,
    String path,
    String checksum,
    int rawBytes,
    bool gzip,
  ) async {
    if (rawBytes > 4 * 1024 * 1024 || rawBytes < 1) {
      throw const FormatException('交通データの容量上限を超えています');
    }
    Uint8List? bytes = _memory[key];
    try {
      bytes ??= await store.read(key);
    } catch (_) {
      /* Cache unavailable (private mode, quota, platform): fetch normally. */
    }
    if (bytes != null && sha256.convert(bytes).toString() != checksum) {
      bytes = null;
      try {
        await store.remove(key);
      } catch (_) {}
    }
    if (bytes == null) {
      bytes = await download(path, 4 * 1024 * 1024);
      requests++;
      downloadedBytes += bytes.length;
      if (sha256.convert(bytes).toString() != checksum) {
        throw const FormatException('交通データのチェックサムが一致しません');
      }
    } else {
      cacheHits++;
    }
    final value = await compute(decodeTransportAsset, {
      'bytes': bytes,
      'rawBytes': rawBytes,
      'gzip': gzip,
    });
    if (!_memory.containsKey(key) && bytes.length <= 8 * 1024 * 1024) {
      while (_memory.isNotEmpty &&
          (_memoryBytes + bytes.length > 8 * 1024 * 1024 ||
              _memory.length >= 128)) {
        final first = _memory.keys.first;
        _memoryBytes -= _memory.remove(first)!.length;
      }
      _memory[key] = bytes;
      _memoryBytes += bytes.length;
    }
    try {
      await store.write(key, bytes);
    } catch (_) {}
    return value;
  }
}
