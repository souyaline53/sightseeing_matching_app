import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/catalog_data.dart';
import '../../model/catalog_record.dart';
import '../../model/post.dart';
import '../../repository/cloud_image_repository.dart';
import '../display_image.dart';
import '../image_policy.dart';
import 'catalog_admin_service.dart';
import 'cloud_services.dart';

class ImageOptimizationResult {
  final int optimized, unchanged;
  final List<String> failures;
  const ImageOptimizationResult(this.optimized, this.unchanged, this.failures);
}

final imageOptimizationServiceProvider = Provider(
  (ref) => ImageOptimizationService(ref),
);

class ImageOptimizationService {
  final Ref ref;
  ImageOptimizationService(this.ref);
  Future<ImageOptimizationResult> run(void Function(String) progress) async {
    final cloud = await ref.read(cloudServicesProvider.future);
    cloud.requireAdmin();
    final images = ref.read(cloudImageRepositoryProvider);
    var optimized = 0, unchanged = 0;
    final failures = <String>[];
    Future<void> optimize(
      DocumentSnapshot<Map<String, dynamic>> doc, {
      required bool post,
    }) async {
      final data = doc.data()!;
      final uploaded = <String>[];
      var changed = 0, skipped = 0;
      Future<Map<String, String>> convert(String url, String path) async {
        if (url.isEmpty) return {'url': url, 'path': path};
        if (path.isEmpty) throw StateError('画像の保存パスがありません。');
        final file = cloud.storage.ref(path);
        final meta = await file.getMetadata();
        if (meta.size != null && meta.size! <= maxDisplayImageBytes) {
          skipped++;
          return {'url': url, 'path': path};
        }
        final bytes = await file.getData(maxImageBytes);
        if (bytes == null) throw StateError('画像を取得できませんでした。');
        final parent = path.substring(0, path.lastIndexOf('/'));
        final result = await images.upload(
          '$parent/${newPostId('display-v1')}',
          bytes,
        );
        uploaded.add(result.path);
        changed++;
        return {'url': result.url, 'path': result.path};
      }

      String stamp(Map<String, dynamic> value) => post
          ? jsonEncode(
              (value['media'] as List)
                  .map(
                    (m) => [
                      m['id'],
                      m['source'],
                      m['storagePath'],
                      m['mimeType'],
                    ],
                  )
                  .toList(),
            )
          : jsonEncode([
              value['photo'],
              value['photoPath'],
              value['additionalPhotos'],
              value['additionalPhotoPaths'],
            ]);
      try {
        final update = <String, dynamic>{};
        if (post) {
          final media = <Map<String, dynamic>>[];
          for (final item in data['media'] as List) {
            final photo = await convert(
              item['source'] as String,
              item['storagePath'] as String,
            );
            media.add({
              ...Map<String, dynamic>.from(item),
              'source': photo['url'],
              'storagePath': photo['path'],
              'mimeType': photo['path'] == item['storagePath']
                  ? item['mimeType']
                  : 'image/jpeg',
            });
          }
          update['media'] = media;
        } else {
          final main = await convert(
            data['photo'] as String? ?? '',
            data['photoPath'] as String? ?? '',
          );
          update.addAll({
            'photo': main['url'],
            'photoPath': main['path'],
            'updatedAt': FieldValue.serverTimestamp(),
          });
          if (doc.reference.parent.id == CatalogKind.sightseeing.collection) {
            final urls = <String>[], paths = <String>[];
            final originalUrls = (data['additionalPhotos'] as List? ?? [])
                .cast<String>();
            final originalPaths = (data['additionalPhotoPaths'] as List? ?? [])
                .cast<String>();
            for (var i = 0; i < originalUrls.length; i++) {
              final result = await convert(
                originalUrls[i],
                i < originalPaths.length ? originalPaths[i] : '',
              );
              urls.add(result['url']!);
              paths.add(result['path']!);
            }
            update.addAll({
              'additionalPhotos': urls,
              'additionalPhotoPaths': paths,
            });
          }
        }
        if (changed > 0) {
          await cloud.firestore.runTransaction((transaction) async {
            final current = await transaction.get(doc.reference);
            if (!current.exists || stamp(current.data()!) != stamp(data)) {
              throw StateError('処理中に画像が更新されました。再実行してください。');
            }
            transaction.update(doc.reference, update);
          });
        }
        optimized += changed;
        unchanged += skipped;
        // 旧画像は保存済みの旅程やURLの互換用に残す。通常表示は新URLを使用する。
      } catch (_) {
        failures.add('${doc.reference.parent.id}/${doc.id}');
        for (final path in uploaded) {
          try {
            await images.delete(path);
          } catch (_) {}
        }
      }
    }

    for (final kind in CatalogKind.values) {
      final docs = await cloud.firestore.collection(kind.collection).get();
      for (final doc in docs.docs) {
        progress('${kind.label}：${doc.id}');
        await optimize(doc, post: false);
      }
      ref.invalidate(adminRecordsProvider(kind));
    }
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      Query<Map<String, dynamic>> query = cloud.firestore
          .collection('posts')
          .orderBy(FieldPath.documentId)
          .limit(100);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final page = await query.get();
      if (page.docs.isEmpty) break;
      for (final doc in page.docs) {
        if (doc.data()['status'] != 'active') continue;
        progress('投稿：${doc.id}');
        await optimize(doc, post: true);
      }
      cursor = page.docs.last;
      if (page.docs.length < 100) break;
    }
    ref.invalidate(catalogProvider);
    return ImageOptimizationResult(
      optimized,
      unchanged,
      List.unmodifiable(failures),
    );
  }
}
