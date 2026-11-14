import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../data/catalog_data.dart';
import '../../../state/trip_state.dart';
import '../../../widgets/travel_photo.dart';

class BookmarkTimelineStop extends HookConsumerWidget {
  final TripState trip;
  final int index;
  const BookmarkTimelineStop({
    super.key,
    required this.trip,
    required this.index,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedStop = trip.stops[index];
    final stop =
        ref
            .watch(catalogProvider)
            .value
            ?.experiences
            .where((current) => current.id == savedStop.id)
            .firstOrNull ??
        savedStop;
    final colors = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      key: ValueKey('home-stop-$index'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (index < trip.stops.length - 1)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: colors.primary.withValues(alpha: .25),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        if (stop.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            stop.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (stop.photo.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 54,
                        height: 56,
                        child: TravelPhoto(stop),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
