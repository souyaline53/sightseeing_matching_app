import '../state/trip_library_state.dart';
import '../data/catalog_data.dart';
import '../state/settings_state.dart';
import '../state/discovery_state.dart';
import 'profile/profile_home.dart';
import 'posts/posts_home.dart';
import 'chat/chat_home.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../state/app_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../state/trip_state.dart';
import 'recommendation/recommendation_home.dart';
import 'itinerary/itinerary_home.dart';

class BasePage extends HookConsumerWidget {
  const BasePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatOpened = useState(false);
    final settings = ref.watch(settingsProvider);
    final trips = ref.watch(tripLibraryProvider);
    final catalog = ref.watch(catalogProvider);
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
    final trip = ref.watch(tripProvider);
    final saveFailed = ref.watch(tripSaveErrorProvider);
    final tab = ref.watch(appTabProvider).index;
    final searchStep = ref.watch(
      discoveryProvider.select((state) => state.step),
    );
    return PopScope(
      canPop: tab != 0 || searchStep == 0,
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
                  catalog.hasValue
                      ? const ItineraryHome()
                      : const _CatalogNotice(),
                  catalog.hasValue ? const PostsHome() : const _CatalogNotice(),
                  chatOpened.value || tab == AppTab.chat.index
                      ? const ChatHome()
                      : const SizedBox.shrink(),
                  const ProfileHome(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) {
            if (value == AppTab.chat.index) chatOpened.value = true;
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
            NavigationDestination(
              icon: Badge(
                label: Text('${trip.saved.length}'),
                isLabelVisible: trip.saved.isNotEmpty,
                child: const Icon(Icons.route_outlined),
              ),
              label: '旅程作成',
            ),
            const NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: '投稿',
            ),
            const NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'チャット',
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
