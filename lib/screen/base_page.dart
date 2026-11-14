import '../state/trip_library_state.dart';
import '../data/catalog_data.dart';
import '../state/settings_state.dart';
import '../state/discovery_state.dart';
import 'profile/profile_home.dart';
import 'home/home_screen.dart';
import 'recommendation/swipe_home.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../state/app_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'recommendation/recommendation_home.dart';
import 'itinerary/itinerary_home.dart';

class BasePage extends HookConsumerWidget {
  const BasePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initialized = useRef(false);
    final swipeOpened = useState(false);
    final settings = ref.watch(settingsProvider);
    final trips = ref.watch(tripLibraryProvider);
    final catalog = ref.watch(catalogProvider);
    useEffect(() {
      if (trips.hasValue && !initialized.value) {
        initialized.value = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final completed = trips.requireValue.plans.where(
            (p) => p.stops.isNotEmpty,
          );
          if (completed.isNotEmpty) {
            final active = trips.requireValue.activeTrip;
            if (active == null || active.stops.isEmpty) {
              ref.read(tripLibraryProvider.notifier).select(completed.first.id);
            }
            ref.read(appTabProvider.notifier).select(AppTab.booklet);
          }
        });
      }
      return null;
    }, [trips.hasValue]);
    if (settings.isLoading || trips.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (settings.hasError || trips.hasError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('保存済みデータを読み込めませんでした。データを保護するため、読み込みが完了するまで編集を停止しています。'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    if (settings.hasError) ref.invalidate(settingsProvider);
                    if (trips.hasError) ref.invalidate(tripLibraryProvider);
                  },
                  child: const Text('再読み込み'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final saveFailed = ref.watch(tripSaveErrorProvider);
    final tab = ref.watch(appTabProvider).index;
    final searchStep = ref.watch(
      discoveryProvider.select((state) => state.step),
    );
    return PopScope(
      canPop: tab != AppTab.recommendation.index || searchStep == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && tab == 0 && searchStep > 0) {
          ref.read(discoveryProvider.notifier).back();
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            if (saveFailed)
              MaterialBanner(
                content: const Text('旅程を端末に保存できませんでした。再試行してください。'),
                actions: [
                  TextButton(
                    onPressed: () =>
                        ref.read(tripLibraryProvider.notifier).retrySave(),
                    child: const Text('再試行'),
                  ),
                ],
              ),
            Expanded(
              child: IndexedStack(
                index: tab,
                children: [
                  catalog.hasValue
                      ? const RecommendationHome()
                      : const _CatalogNotice(),
                  catalog.hasValue && swipeOpened.value
                      ? const SwipeHome()
                      : const SizedBox.shrink(),
                  catalog.hasValue
                      ? const HomeScreen()
                      : const _CatalogNotice(),
                  catalog.hasValue
                      ? ItineraryHome(active: tab == AppTab.itinerary.index)
                      : const _CatalogNotice(),
                  const ProfileHome(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) {
            if (value == AppTab.swipe.index) swipeOpened.value = true;
            if (value == AppTab.recommendation.index) {
              ref.read(discoveryProvider.notifier).reset();
            }
            ref.read(appTabProvider.notifier).select(AppTab.values[value]);
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'ホーム',
            ),
            const NavigationDestination(
              icon: Icon(Icons.style_outlined),
              selectedIcon: Icon(Icons.style),
              label: 'スワイプ',
            ),
            const NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: '旅のしおり',
            ),
            const NavigationDestination(
              icon: Icon(Icons.route_outlined),
              selectedIcon: Icon(Icons.route),
              label: '旅程作成',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'プロフィール',
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogNotice extends HookConsumerWidget {
  const _CatalogNotice();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('TABISAKI')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: catalog.isLoading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'クラウドの観光地情報を読み込めませんでした。Firebaseの設定・ルール・通信を確認してください。プロフィールは引き続き開けます。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(catalogProvider),
                      child: const Text('再読み込み'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
