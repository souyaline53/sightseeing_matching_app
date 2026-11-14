import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/trip_library_state.dart';
import '../../theme/app_theme.dart';
import '../../navigation/travel_navigation.dart';
import '../shared/trips/trips_drawer.dart';
import 'chat/chat_home.dart';
import 'posts/posts_home.dart';
import 'widgets/bookmark_empty_state.dart';
import 'widgets/bookmark_trip_hero.dart';
import 'widgets/bookmark_timeline.dart';

class BookmarkHome extends HookConsumerWidget {
  const BookmarkHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(tripLibraryProvider).requireValue;
    final active = library.activeTrip;
    final trip = active != null && active.stops.isNotEmpty ? active : null;
    void search() => beginInterestSearch(ref);

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
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    key: PageStorageKey('bookmark-${trip.id}'),
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 18),
                        child: Text(
                          'あなたの次の旅行プラン',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      BookmarkTripHero(trip: trip),
                      const SizedBox(height: 24),
                      BookmarkTimeline(key: ValueKey(trip.id), trip: trip),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
