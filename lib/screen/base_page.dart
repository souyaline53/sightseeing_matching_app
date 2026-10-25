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
    final trip = ref.watch(tripProvider);
    final tab = ref.watch(appTabProvider).index;
    return Scaffold(
      body: IndexedStack(
        index: tab,
        children: [const RecommendationHome(), const ItineraryHome()],
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
        ],
      ),
    );
  }
}
