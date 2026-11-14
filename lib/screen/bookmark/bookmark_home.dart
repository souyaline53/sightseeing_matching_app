import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/app_tab.dart';
import '../../state/trip_library_state.dart';
import '../../state/trip_state.dart';
import '../../navigation/travel_navigation.dart';
import '../shared/trips/plan_screen.dart';
import '../shared/trips/trips_drawer.dart';
import 'chat/chat_home.dart';
import 'posts/posts_home.dart';
import 'widgets/bookmark_empty_state.dart';
import 'widgets/bookmark_trip_hero.dart';
import 'widgets/bookmark_sheet.dart';

class BookmarkHome extends HookConsumerWidget {
  const BookmarkHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(tripLibraryProvider).requireValue;
    final active = library.activeTrip;
    final trip = active != null && active.stops.isNotEmpty ? active : null;
    void search() => beginInterestSearch(ref);

    void edit() {
      if (trip == null) return;
      ref.read(tripProvider.notifier).openPlan(trip.id);
      ref.read(appTabProvider.notifier).select(AppTab.itinerary);
    }

    void open() {
      if (trip == null) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlanScreen(
            tripId: trip.id,
            stops: trip.stops,
            origin: trip.origin,
            date: trip.travelDate,
            publicTransport: trip.publicTransport,
            demo: false,
            conditions: trip.conditions,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: '旅の一覧を開く',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu),
          ),
        ),
        title: const FittedBox(fit: BoxFit.scaleDown, child: Text('旅のしおり')),
        actions: [
          IconButton(
            tooltip: 'チャット',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const ChatHome())),
            icon: const Icon(Icons.chat_bubble_outline, size: 21),
          ),
          IconButton(
            tooltip: '投稿',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const PostsHome())),
            icon: const Icon(Icons.edit_square, size: 21),
          ),
          if (trip != null) TripActionsMenu(trip: trip),
        ],
      ),
      drawer: TripsDrawer(onNewTrip: search),
      body: SafeArea(
        top: false,
        child: trip == null
            ? BookmarkEmptyState(onSearch: search)
            : LayoutBuilder(
                builder: (context, constraints) {
                  // Reserve space for the independently scrolling booklet.
                  final extraTextHeight = math.max(
                    0.0,
                    MediaQuery.textScalerOf(context).scale(180) - 180,
                  );
                  final heroHeight = math.min(
                    (constraints.maxHeight * .37).clamp(190.0, 260.0) +
                        extraTextHeight,
                    constraints.maxHeight * .45,
                  );
                  const overlap = 24.0;
                  return Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: heroHeight,
                        child: BookmarkTripHero(trip: trip),
                      ),
                      Positioned(
                        top: heroHeight - overlap,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: BookmarkSheet(
                          key: ValueKey('sheet-${trip.id}'),
                          trip: trip,
                          onOpen: trip.stops.isEmpty ? edit : open,
                          onSeeAll: open,
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
