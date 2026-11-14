import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../state/trip_state.dart';
import 'bookmark_timeline_stop.dart';

class BookmarkSheet extends HookConsumerWidget {
  final TripState trip;
  final VoidCallback onOpen, onSeeAll;
  const BookmarkSheet({
    super.key,
    required this.trip,
    required this.onOpen,
    required this.onSeeAll,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scroll = useScrollController();
    return Material(
      key: const ValueKey('home-booklet-sheet'),
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '旅のしおり（${trip.stops.length}スポット）',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (trip.stops.length > 3)
                  TextButton(onPressed: onSeeAll, child: const Text('すべて見る')),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: trip.stops.isEmpty
                  ? const Center(
                      child: Text('まだスポットがありません', textAlign: TextAlign.center),
                    )
                  : Scrollbar(
                      controller: scroll,
                      child: ListView.builder(
                        key: PageStorageKey('home-stops-${trip.id}'),
                        controller: scroll,
                        padding: EdgeInsets.zero,
                        itemCount: trip.stops.length,
                        itemBuilder: (context, index) =>
                            BookmarkTimelineStop(trip: trip, index: index),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('home-open-booklet'),
              onPressed: onOpen,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('旅のしおりを開く'),
            ),
          ],
        ),
      ),
    );
  }
}
