import 'dart:convert';
import 'dart:typed_data';
import 'package:sembast/sembast.dart';
import '../model/post.dart';
import 'posts/posts_database.dart';

abstract interface class PostsRepository {
  Future<PostsState?> load();
  Future<void> save(
    PostsState state, {
    Map<String, Uint8List> media = const {},
    Set<String> removeMedia = const {},
  });
  Future<Uint8List?> readMedia(String id);
  Future<void> close();
}

/// IndexedDB on Web, an app-local database file on mobile. No Firebase access.
class LocalPostsRepository implements PostsRepository {
  final Future<Database> Function() open;
  Future<Database>? _database;
  LocalPostsRepository({Future<Database> Function()? open})
    : open = open ?? openPostsDatabase;
  Future<Database> get database => _database ??= open();
  final _state = stringMapStoreFactory.store('posts_state');
  final _media = stringMapStoreFactory.store('post_media');

  @override
  Future<PostsState?> load() async {
    final data = await _state.record('main').get(await database);
    return data == null
        ? null
        : PostsState.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<void> save(
    PostsState state, {
    Map<String, Uint8List> media = const {},
    Set<String> removeMedia = const {},
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await _state.record('main').put(txn, state.toJson());
      for (final entry in media.entries) {
        await _media.record(entry.key).put(txn, {
          'bytes': base64Encode(entry.value),
        });
      }
      for (final id in removeMedia) {
        await _media.record(id).delete(txn);
      }
    });
  }

  @override
  Future<Uint8List?> readMedia(String id) async {
    final record = await _media.record(id).get(await database);
    return record == null ? null : base64Decode(record['bytes'] as String);
  }

  @override
  Future<void> close() async {
    final db = _database;
    if (db == null) return;
    Database opened;
    try {
      opened = await db;
    } catch (_) {
      return;
    }
    await opened.close();
  }
}
