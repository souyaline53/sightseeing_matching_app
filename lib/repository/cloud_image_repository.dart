import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../service/cloud/cloud_services.dart';
import '../service/image_policy.dart';
import '../service/display_image.dart';

class CloudImage {
  final String url, path;
  const CloudImage(this.url, this.path);
}

abstract interface class CloudImageRepository {
  Future<String> postOwner();
  Future<CloudImage> upload(String pathPrefix, Uint8List bytes);
  Future<void> delete(String path);
}

class FirebaseCloudImageRepository implements CloudImageRepository {
  final Future<CloudServices> Function() services;
  FirebaseCloudImageRepository(this.services);
  @override
  Future<String> postOwner() async => (await (await services()).writer()).uid;
  @override
  Future<CloudImage> upload(String pathPrefix, Uint8List bytes) async {
    await validateImage(bytes);
    final displayBytes = await createDisplayImage(bytes);
    final cloud = await services();
    final path = '$pathPrefix.jpg';
    final reference = cloud.storage.ref(path);
    await reference.putData(
      displayBytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: displayImageCacheControl,
      ),
    );
    try {
      return CloudImage(await reference.getDownloadURL(), path);
    } catch (_) {
      await reference.delete();
      rethrow;
    }
  }

  @override
  Future<void> delete(String path) async {
    if (path.isEmpty) return;
    try {
      await (await services()).storage.ref(path).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }
}

final cloudImageRepositoryProvider = Provider<CloudImageRepository>(
  (ref) => FirebaseCloudImageRepository(
    () => ref.read(cloudServicesProvider.future),
  ),
);
