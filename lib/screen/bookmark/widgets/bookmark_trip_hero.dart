import 'package:flutter/material.dart';
import '../../../model/search_settings.dart';
import '../../../state/trip_state.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/travel_photo.dart';
import '../../shared/trips/trips_drawer.dart';

class BookmarkTripHero extends StatelessWidget {
  final TripState trip;
  const BookmarkTripHero({super.key, required this.trip});
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('home-trip-hero'),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(26),
      boxShadow: const [
        BoxShadow(
          color: Color(0x20a64708),
          blurRadius: 15,
          offset: Offset(0, 5),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            Positioned.fill(child: TravelPhoto(trip.stops.first)),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black12, Colors.black87],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 140),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '次の旅行',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      trip.displayTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _HeroDetail(Icons.calendar_today_outlined, tripDateLabel(trip)),
              _HeroDetail(
                trip.publicTransport
                    ? Icons.train_outlined
                    : Icons.directions_car_outlined,
                '${trip.origin} 発 · ${trip.conditions.transport.label}',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HeroDetail extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeroDetail(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 17, color: AppColors.primary),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}
