import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../model/search_settings.dart';
import '../../../state/trip_state.dart';
import '../../../widgets/travel_photo.dart';
import '../../shared/trips/trips_drawer.dart';

class BookmarkTripHero extends HookConsumerWidget {
  final TripState trip;
  const BookmarkTripHero({super.key, required this.trip});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = trip.stops.firstOrNull ?? trip.saved.firstOrNull;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        key: const ValueKey('home-trip-hero'),
        fit: StackFit.expand,
        children: [
          if (photo != null)
            TravelPhoto(photo)
          else
            ColoredBox(
              color: colors.primaryContainer,
              child: Icon(
                Icons.landscape_outlined,
                size: 88,
                color: colors.primary,
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black12, Colors.black87],
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 42,
            top: 16,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: SizedBox(
                  width: constraints.maxWidth - 44,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.stops.isEmpty ? '次の旅  ·  作成中' : '次の旅',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        trip.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tripDateLabel(trip),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${trip.origin} 発  ·  ${trip.conditions.transport.label}  ·  ${trip.conditions.length.label}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
