import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sightseeing_matching_app/data/catalog_data.dart';
import 'package:sightseeing_matching_app/service/ai_matching_service.dart';
import 'package:sightseeing_matching_app/state/additional_discovery_cache.dart';
import 'package:sightseeing_matching_app/state/discovery_state.dart';
import 'test_support.dart';

class _ExistingDiscovery extends DiscoveryNotifier {
  @override
  DiscoveryState build() => DiscoveryState(
    step: 3,
    index: 1,
    deck: testCatalog.experiences.take(3).toList(),
    recommendationReasons: {testCatalog.experiences.first.id: '保存した推薦理由'},
  );
}

void main() {
  initializeCatalogTests();

  test(
    'reuse existing cards and preserve browsing independently of main search',
    () async {
      var calls = 0;
      final parent = ProviderContainer(
        overrides: [
          discoveryProvider.overrideWith(_ExistingDiscovery.new),
          aiMatchingServiceProvider.overrideWithValue(
            AiMatchingService(
              invoke: (_) async {
                calls++;
                return {'recommendations': []};
              },
            ),
          ),
        ],
      );
      addTearDown(parent.dispose);
      final original = parent.read(discoveryProvider);
      final cache = parent.read(additionalDiscoveryCacheProvider);
      final session = cache.session('trip', parent);
      final flow =
          session.read(discoveryProvider.notifier) as AdditionalDiscovery;
      await flow.ensureLoaded({});
      expect(calls, 0);
      expect(session.read(discoveryProvider).index, 1);
      expect(
        session.read(discoveryProvider).recommendationReasons,
        original.recommendationReasons,
      );
      flow.advance();
      expect(parent.read(discoveryProvider), same(original));
      expect(cache.session('trip', parent), same(session));
      await flow.ensureLoaded({});
      expect(session.read(discoveryProvider).index, 2);
      expect(calls, 0);
    },
  );

  test(
    'one request survives reopening; disposing cache permits a new request',
    () async {
      var calls = 0;
      final response = Completer<void>();
      final parent = ProviderContainer(
        overrides: [
          catalogProvider.overrideWith((ref) => Stream.value(testCatalog)),
          aiMatchingServiceProvider.overrideWithValue(
            AiMatchingService(
              invoke: (_) async {
                calls++;
                await response.future;
                return {
                  'recommendations': [
                    {
                      'spot_id': testCatalog.experiences.first.id,
                      'reason': '推薦理由',
                    },
                  ],
                };
              },
            ),
          ),
        ],
      );
      addTearDown(parent.dispose);
      final session = parent
          .read(additionalDiscoveryCacheProvider)
          .session('trip', parent);
      final flow =
          session.read(discoveryProvider.notifier) as AdditionalDiscovery;
      final pending = flow.ensureLoaded({});
      await flow.ensureLoaded({});
      expect(calls, 1);
      expect(
        parent.read(additionalDiscoveryCacheProvider).session('trip', parent),
        same(session),
      );
      parent.listen(catalogProvider, (_, _) {});
      await parent
          .read(catalogProvider.future)
          .timeout(const Duration(seconds: 5));
      response.complete();
      await pending.timeout(const Duration(seconds: 5));
      flow.advance();
      await flow.ensureLoaded({});
      expect(calls, 1);
      expect(session.read(discoveryProvider).index, 1);
      parent.invalidate(additionalDiscoveryCacheProvider);
      final replacement = parent
          .read(additionalDiscoveryCacheProvider)
          .session('trip', parent);
      expect(replacement, isNot(same(session)));
      await (replacement.read(discoveryProvider.notifier)
              as AdditionalDiscovery)
          .ensureLoaded({});
      expect(calls, 2);
      expect(replacement.read(discoveryProvider).deck, hasLength(1));
    },
  );
}
