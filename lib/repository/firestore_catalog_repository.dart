import 'dart:async';
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
    final lists = await Future.wait(CatalogKind.values.map(records));
    return TravelCatalog(
      experiences: lists[0].map((e) => e.toExperience()).toList(),
      transit: lists[1].map((e) => e.toTransit()).toList(),
    );
  }

  @override
  Stream<TravelCatalog> watch() async* {
    final cloud = await services();
    final controller = StreamController<TravelCatalog>();
    final current = <CatalogKind, List<CatalogRecord>>{};
    var closed = false;
    void accept(
      CatalogKind kind,
      QuerySnapshot<Map<String, dynamic>> snapshot,
    ) {
      if (closed) return;
      try {
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
        current[kind] = records;
        if (current.length == 2) {
          controller.add(
            TravelCatalog(
              experiences: current[CatalogKind.sightseeing]!
                  .map((r) => r.toExperience())
                  .toList(),
              transit: current[CatalogKind.transit]!
                  .map((r) => r.toTransit())
                  .toList(),
            ),
          );
        }
      } catch (error, stack) {
        controller.addError(error, stack);
      }
    }

    final subscriptions = [
      for (final kind in CatalogKind.values)
        cloud.firestore
            .collection(kind.collection)
            .snapshots()
            .listen(
              (snapshot) => accept(kind, snapshot),
              onError: (Object error, StackTrace stack) {
                if (!closed) controller.addError(error, stack);
              },
            ),
    ];
    try {
      yield* controller.stream;
    } finally {
      closed = true;
      await Future.wait(subscriptions.map((s) => s.cancel()));
      await controller.close();
    }
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
