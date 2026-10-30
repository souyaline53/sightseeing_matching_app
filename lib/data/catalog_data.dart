import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/travel_catalog.dart';
import '../repository/catalog_repository.dart';
import '../repository/firestore_catalog_repository.dart';
import '../service/cloud/cloud_services.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) =>
      FirestoreCatalogRepository(() => ref.read(cloudServicesProvider.future)),
);
final catalogProvider = StreamProvider<TravelCatalog>(
  (ref) => ref.watch(catalogRepositoryProvider).watch(),
);
