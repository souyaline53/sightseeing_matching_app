import '../../model/spot_visit_info.dart';
import '../../data/departure_places.dart';
import '../../repository/transport_repository.dart';
import 'dart:typed_data';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/catalog_data.dart';
import '../../model/catalog_record.dart';
import '../../model/post.dart';
import '../../repository/cloud_image_repository.dart';
import '../../repository/firestore_catalog_repository.dart';
import 'cloud_services.dart';

class CatalogPhotoDraft {
  final String url, path;
  final Uint8List? bytes;
  const CatalogPhotoDraft({this.url = '', this.path = '', this.bytes});
}

final adminCatalogRepositoryProvider = Provider(
  (ref) =>
      FirestoreCatalogRepository(() => ref.read(cloudServicesProvider.future)),
);
final adminRecordsProvider = FutureProvider.autoDispose
    .family<List<CatalogRecord>, CatalogKind>(
      (ref, kind) => ref.watch(adminCatalogRepositoryProvider).records(kind),
    );
final catalogAdminServiceProvider = Provider((ref) => CatalogAdminService(ref));

class CatalogAdminService {
  final Ref ref;
  CatalogAdminService(this.ref);
  Future<List<String>> _remove(Iterable<String> paths) async {
    final failed = <String>[];
    for (final path in paths.where((path) => path.isNotEmpty).toSet()) {
      try {
        await ref.read(cloudImageRepositoryProvider).delete(path);
      } catch (_) {
        failed.add(path);
      }
    }
    return failed;
  }

  void _refresh(CatalogKind kind) {
    ref.invalidate(adminRecordsProvider(kind));
    ref.invalidate(catalogProvider);
    if (kind == CatalogKind.departure) {
      ref.invalidate(departurePlacesProvider);
      ref.invalidate(originTransportStopsProvider);
    }
  }

  Future<List<String>> save(
    CatalogKind kind,
    String id,
    Map<String, dynamic> values,
    List<CatalogPhotoDraft> photos, {
    CatalogRecord? original,
  }) async {
    (await ref.read(cloudServicesProvider.future)).requireAdmin();
    if (values['latitude'] == null ||
        values['longitude'] == null ||
        values['address'] is! String) {
      throw StateError('住所の変換を行うか、緯度・経度を指定してください。');
    }
    final error = validateCatalogRecord(kind, id, values);
    if (error != null) throw StateError(error);
    if (kind == CatalogKind.departure) {
      if (photos.isNotEmpty) throw StateError('出発地に写真は登録できません。');
      await ref
          .read(adminCatalogRepositoryProvider)
          .save(kind, id, values, creating: original == null);
      _refresh(kind);
      return [];
    }
    SpotVisitInfo.fromMap(values).validate();
    if (photos.length > (kind == CatalogKind.sightseeing ? 6 : 1)) {
      throw StateError('写真の枚数を確認してください。');
    }
    final uploaded = <String>[];
    final saved = <CloudCatalogPhoto>[];
    try {
      for (final photo in photos) {
        if (photo.bytes == null) {
          if (!photo.path.startsWith('catalog/${kind.collection}/$id/') ||
              !photo.url.startsWith('http')) {
            throw StateError('写真をアップロードし直してください。');
          }
          saved.add(CloudCatalogPhoto(photo.url, photo.path));
        } else {
          final image = await ref
              .read(cloudImageRepositoryProvider)
              .upload(
                'catalog/${kind.collection}/$id/${newPostId('image')}',
                photo.bytes!,
              );
          uploaded.add(image.path);
          saved.add(CloudCatalogPhoto(image.url, image.path));
        }
      }
      await ref.read(adminCatalogRepositoryProvider).save(kind, id, {
        ...values,
        'photo': saved.firstOrNull?.url ?? '',
        'photoPath': saved.firstOrNull?.path ?? '',
        if (kind == CatalogKind.sightseeing)
          'additionalPhotos': saved.skip(1).map((e) => e.url).toList(),
        if (kind == CatalogKind.sightseeing)
          'additionalPhotoPaths': saved.skip(1).map((e) => e.path).toList(),
      }, creating: original == null);
    } catch (_) {
      await _remove(uploaded);
      rethrow;
    }
    _refresh(kind);
    final retained = saved.map((e) => e.path).toSet();
    return _remove(
      (original?.photos ?? [])
          .map((e) => e.path)
          .where((path) => !retained.contains(path)),
    );
  }

  Future<List<String>> delete(CatalogRecord record) async {
    await ref.read(adminCatalogRepositoryProvider).delete(record);
    _refresh(record.kind);
    return _remove(record.photos.map((e) => e.path));
  }
}
