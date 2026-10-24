import 'package:flutter/material.dart';
import '../state/trip_state.dart';
import 'recommendation/recommendation_home.dart';
import 'itinerary/itinerary_home.dart';

class BasePage extends StatefulWidget {
  const BasePage({super.key});
  @override
  State<BasePage> createState() => _BasePageState();
}

class _BasePageState extends State<BasePage> {
  final trip = TripState();
  int tab = 0;
  @override
  void dispose() {
    trip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: trip,
    builder: (context, _) => Scaffold(
      body: IndexedStack(
        index: tab,
        children: [
          RecommendationHome(trip: trip),
          ItineraryHome(trip: trip),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
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
    ),
  );
}
