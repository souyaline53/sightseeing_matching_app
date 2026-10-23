import 'package:flutter/material.dart';
//import 'package:persistent_bottom_nav_bar_v2/persistent-tab-view.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:sightseeing_matching_app/screen/chat/chat_home.dart';
import 'package:sightseeing_matching_app/screen/recommendation/recommendation_home.dart';
import 'package:sightseeing_matching_app/screen/itinerary/itinerary_home.dart';
import 'package:sightseeing_matching_app/screen/profile/profile_home.dart';

class BasePage extends StatelessWidget {
  const BasePage({super.key});

  @override
  Widget build(BuildContext context) {
    final pages = [
      RecommendationHome(),
      ItineraryHome(),
      ChatHome(),
      const ProfileHome(),
    ];

    return Scaffold(
      body: PersistentTabView(
        context,
        screens: pages,
        navBarStyle: NavBarStyle.simple,
        backgroundColor: Colors.white,
        items: [
          PersistentBottomNavBarItem(
            icon: const Icon(
              Icons.home,
            ),
            inactiveIcon: const Icon(
              Icons.home,
            ),
            title: 'ホーム',
            activeColorPrimary: Colors.blue,
            inactiveColorPrimary: Theme.of(context).disabledColor,
          ),
          PersistentBottomNavBarItem(
            icon: const Icon(
              Icons.calendar_month,
            ),
            inactiveIcon: const Icon(
              Icons.calendar_month,
            ),
            title: 'カレンダー',
            activeColorPrimary: Colors.blue,
            inactiveColorPrimary: Theme.of(context).disabledColor,
          ),
          PersistentBottomNavBarItem(
            icon: const Icon(
              Icons.calculate,
            ),
            inactiveIcon: const Icon(
              Icons.calculate,
            ),
            title: '推移',
            activeColorPrimary: Colors.blue,
            inactiveColorPrimary: Theme.of(context).disabledColor,
          ),
          PersistentBottomNavBarItem(
            icon: const Icon(
              Icons.settings,
            ),
            inactiveIcon: const Icon(
              Icons.settings,
            ),
            title: '設定',
            activeColorPrimary: Colors.blue,
            inactiveColorPrimary: Theme.of(context).disabledColor,
          ),


        ],
      ),
    );
  }
}
