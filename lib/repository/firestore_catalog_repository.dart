import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/catalog_record.dart';
import '../model/travel_catalog.dart';
import '../service/cloud/cloud_services.dart';
import 'catalog_repository.dart';

class FirestoreCatalogRepository implements CatalogRepository {
  final Future<CloudServices> Function() services;
  FirestoreCatalogRepository(this.services);
  Future<List<CatalogRecord>> records(CatalogKind kind) async {
    final cloud = await services();
    final snapshot = await cloud.firestore
        .collection(kind.collection)
        .get(const GetOptions(source: Source.server));
    final records =
        snapshot.docs.map((doc) {
          final error = validateCatalogRecord(kind, doc.id, doc.data());
          if (error != null) {
            throw FormatException('${kind.label}/${doc.id}: $error');
          }
          return CatalogRecord(doc.id, kind, doc.data());
        }).toList()..sort((a, b) {
          final order = a.order.compareTo(b.order);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
    return records;
  }

  @override
  Future<TravelCatalog> load() async {
    final spots = await records(CatalogKind.sightseeing);
    return TravelCatalog(
      experiences: spots.map((e) => e.toExperience()).toList(),
    );
  }

  @override
  Stream<TravelCatalog> watch() async* {
    final cloud = await services();
    yield* cloud.firestore
        .collection(CatalogKind.sightseeing.collection)
        .snapshots()
        .map((snapshot) {
          final records =
              snapshot.docs.map((doc) {
                final error = validateCatalogRecord(
                  CatalogKind.sightseeing,
                  doc.id,
                  doc.data(),
                );
                if (error != null) {
                  throw FormatException('観光地/${doc.id}: $error');
                }
                return CatalogRecord(
                  doc.id,
                  CatalogKind.sightseeing,
                  doc.data(),
                );
              }).toList()..sort((a, b) {
                final order = a.order.compareTo(b.order);
                return order == 0 ? a.id.compareTo(b.id) : order;
              });
          return TravelCatalog(
            experiences: records.map((r) => r.toExperience()).toList(),
          );
        });
  }

  Future<void> save(
    CatalogKind kind,
    String id,
    Map<String, dynamic> data, {
    required bool creating,
  }) async {
    final error = validateCatalogRecord(kind, id, data);
    if (error != null) throw StateError(error);
    final cloud = await services();
    cloud.requireAdmin();
    final doc = cloud.firestore.collection(kind.collection).doc(id);
    await cloud.firestore.runTransaction((transaction) async {
      final current = await transaction.get(doc);
      if (creating && current.exists) {
        throw StateError('同じIDが存在します。別のIDを指定してください。');
      }
      if (!creating && !current.exists) throw StateError('このデータは既に削除されています。');
      transaction.set(doc, {
        ...?current.data(),
        ...data,
        'createdAt':
            current.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> delete(CatalogRecord record) async {
    final cloud = await services();
    cloud.requireAdmin();
    await cloud.firestore
        .collection(record.kind.collection)
        .doc(record.id)
        .delete();
  }
}
