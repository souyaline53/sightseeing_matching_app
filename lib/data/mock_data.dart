import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/mock_catalog.dart';
import '../repository/mock_catalog_repository.dart';

final mockCatalogRepositoryProvider = Provider<MockCatalogRepository>(
  (ref) => MarkdownMockCatalogRepository(),
);
final mockCatalogProvider = FutureProvider<MockCatalog>(
  (ref) => ref.watch(mockCatalogRepositoryProvider).load(),
);
