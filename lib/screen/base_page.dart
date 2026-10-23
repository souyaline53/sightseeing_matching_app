import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:sightseeing_matching_app/provider/app_tab_provider.dart';
import 'package:sightseeing_matching_app/screen/chat/chat_home.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_home.dart';
import 'package:sightseeing_matching_app/screen/profile/profile_home.dart';
import 'package:sightseeing_matching_app/screen/recommendation/recommendation_home.dart';

class BasePage extends HookConsumerWidget {
  const BasePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useMemoized(
      () =>
          PersistentTabController(initialIndex: ref.read(appTabProvider).index),
    );

    // Riverpod側からのタブ変更もナビゲーションに反映する。
    ref.listen(appTabProvider, (previous, next) {
      controller.jumpToTab(next.index);
    });

    useEffect(() {
      void syncSelectedTab() {
        ref
            .read(appTabProvider.notifier)
            .select(AppTab.values[controller.index]);
      }

      controller.addListener(syncSelectedTab);
      return () {
        controller.removeListener(syncSelectedTab);
        controller.dispose();
      };
    }, [controller]);

    final colors = Theme.of(context).colorScheme;

    return PersistentTabView(
      context,
      controller: controller,
      screens: const [
        RecommendationHome(),
        ItineraryHome(),
        ChatHome(),
        ProfileHome(),
      ],
      navBarStyle: NavBarStyle.simple,
      backgroundColor: colors.surface,
      items: [
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.explore),
          inactiveIcon: const Icon(Icons.explore_outlined),
          title: 'おすすめ',
          activeColorPrimary: colors.primary,
          inactiveColorPrimary: colors.onSurfaceVariant,
        ),
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.map),
          inactiveIcon: const Icon(Icons.map_outlined),
          title: '旅程',
          activeColorPrimary: colors.primary,
          inactiveColorPrimary: colors.onSurfaceVariant,
        ),
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.chat_bubble),
          inactiveIcon: const Icon(Icons.chat_bubble_outline),
          title: 'チャット',
          activeColorPrimary: colors.primary,
          inactiveColorPrimary: colors.onSurfaceVariant,
        ),
        PersistentBottomNavBarItem(
          icon: const Icon(Icons.person),
          inactiveIcon: const Icon(Icons.person_outline),
          title: 'プロフィール',
          activeColorPrimary: colors.primary,
          inactiveColorPrimary: colors.onSurfaceVariant,
        ),
      ],
    );
  }
}
