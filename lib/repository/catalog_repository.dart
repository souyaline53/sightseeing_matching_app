import '../model/travel_catalog.dart';

abstract interface class CatalogRepository {
  Future<TravelCatalog> load();
  Stream<TravelCatalog> watch();
}
