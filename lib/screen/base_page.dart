import '../state/settings_state.dart';
import '../state/discovery_state.dart';
import 'profile/profile_home.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../state/app_tab.dart';
import 'package:flutter/material.dart';
import '../state/trip_state.dart';
import 'recommendation/recommendation_home.dart';
import 'itinerary/itinerary_home.dart';

class BasePage extends HookConsumerWidget {
  const BasePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    if (settings.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (settings.hasError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '保存済み設定を読み込めませんでした。データを保護するため、読み込みが完了するまで編集を停止しています。',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(settingsProvider),
                  child: const Text('再読み込み'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final trip = ref.watch(tripProvider);
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
        body: IndexedStack(
          index: tab,
          children: [
            const RecommendationHome(),
            const ItineraryHome(),
            const ProfileHome(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) =>
              ref.read(appTabProvider.notifier).select(AppTab.values[value]),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: '発見する',
            ),
            NavigationDestination(
              icon: Badge(
                label: Text('${trip.saved.length}'),
                isLabelVisible: trip.saved.isNotEmpty,
                child: const Icon(Icons.route_outlined),
              ),
              label: '旅を組み立てる',
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
