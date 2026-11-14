import '../../../theme/app_theme.dart';
import '../../../model/ai_trip_segment.dart';
import '../../shared/transport/ai_transport_card.dart';
import '../../../state/itinerary_navigation.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/departure_places.dart';
import '../../../service/transport/external_directions.dart';
import '../../../widgets/travel_photo.dart';
import '../../shared/experiences/experience_detail.dart';
import '../../../repository/transport_journey_repository.dart';
import '../../../repository/transport_repository.dart';
import '../../../service/transport/itinerary_transport_options.dart';
import '../../../model/transport_journey.dart';
import '../../shared/transport/transport_journey_panel.dart';
import '../../../model/stop_selection.dart';
import '../../../data/catalog_data.dart';
import '../../../model/transport.dart';
import '../../../model/search_settings.dart';
import '../../shared/trips/trips_drawer.dart';
import '../../../state/app_tab.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/material.dart';
import '../../../model/experience.dart';
import '../../../state/trip_state.dart';

class BookmarkTimeline extends HookConsumerWidget {
  final TripState trip;
  const BookmarkTimeline({super.key, required this.trip});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final livePlan = trip;
    final catalog = ref.watch(catalogProvider).value;
    final stops = livePlan.stops
        .map(
          (spot) =>
              catalog?.experiences
                  .where((current) => current.id == spot.id)
                  .firstOrNull ??
              spot,
        )
        .toList();
    final origin = livePlan.origin;
    final publicTransport = livePlan.publicTransport;
    final originProvider = originTransportStopsProvider(origin);
    final originStops = ref.exists(originProvider)
        ? ref.watch(originProvider).value
        : null;
    final departure = departureNamed(
      origin,
      ref.watch(departurePlacesProvider).value ?? const <DeparturePlace>[],
    );
    final originPoint = Experience(
      livePlan.originEndpointId,
      origin,
      '',
      '',
      '',
      '',
      '',
      '',
      0,
      latitude: departure?.point.latitude,
      longitude: departure?.point.longitude,
      accessStops: [
        for (final stop in originStops ?? <TransportStop>[])
          AccessStop({'walkingMinutes': null, ...stop.data, 'stopId': stop.id}),
      ],
    );
    void editPlan({int? transportSegment}) {
      ref.read(tripProvider.notifier).openPlan(trip.id);
      if (transportSegment != null) {
        ref
            .read(itineraryTransportRequestProvider.notifier)
            .open(transportSegment);
      }
      ref.read(appTabProvider.notifier).select(AppTab.itinerary);
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    final arrivalName = livePlan.arrivalPlace;
    final arrivalPlace = departureNamed(
      arrivalName,
      ref.watch(departurePlacesProvider).value ?? const <DeparturePlace>[],
    );
    final arrivalPoint = arrivalName == origin
        ? originPoint
        : Experience(
            livePlan.destinationEndpointId,
            arrivalName,
            '',
            '',
            '',
            '',
            '',
            '',
            0,
            latitude: arrivalPlace?.point.latitude,
            longitude: arrivalPlace?.point.longitude,
            accessStops: arrivalPlace?.accessStops ?? [],
          );
    final points = [originPoint, ...stops, arrivalPoint];
    final segments = [
      for (var i = 0; i < points.length - 1; i++)
        if (stops.isNotEmpty)
          _PlanSegment.resolve(ref, livePlan, points[i], points[i + 1]),
    ];

    return Column(
      key: const ValueKey('bookmark-timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppColors.softSurface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tripDateLabel(trip),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trip.conditions.length.label,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        _TimelineRow(
          label: transportTime(trip.departureMinutes),
          first: true,
          child: _Endpoint(
            name: '$origin を出発',
            publicTransport: publicTransport,
          ),
        ),
        for (var i = 0; i < stops.length; i++) ...[
          _TimelineRow(
            child: _SegmentRow(
              key: PageStorageKey('${trip.id}-transport-$i'),
              segment: segments[i],
              publicTransport: publicTransport,
              onChoose: () => editPlan(transportSegment: i == 0 ? -1 : i - 1),
            ),
          ),
          _TimelineRow(
            label: segments[i].arrival == null
                ? '—'
                : transportTime(segments[i].arrival),
            child: _StopCard(
              key: ValueKey('bookmark-stop-$i'),
              spot: stops[i],
              minutes: trip.stayMinutes[stops[i].id] ?? stops[i].minutes,
              onTap: () => showExperience(context, stops[i]),
            ),
          ),
        ],
        if (segments.isNotEmpty) ...[
          _TimelineRow(
            child: _SegmentRow(
              key: PageStorageKey('${trip.id}-transport-return'),
              segment: segments.last,
              publicTransport: publicTransport,
              onChoose: () => editPlan(transportSegment: -2),
            ),
          ),
          _TimelineRow(
            label: segments.last.arrival == null
                ? '—'
                : transportTime(segments.last.arrival),
            last: true,
            child: _Endpoint(
              name: '$arrivalName に到着',
              publicTransport: publicTransport,
            ),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.tonalIcon(
          key: const ValueKey('bookmark-edit'),
          onPressed: editPlan,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('旅程を編集する'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _PlanSegment {
  final Experience from, to;
  final bool walking;
  final TransportSelection? selection;
  final AiTripSegment? ai;
  const _PlanSegment(
    this.from,
    this.to,
    this.walking,
    this.selection, [
    this.ai,
  ]);
  factory _PlanSegment.resolve(
    WidgetRef ref,
    TripState? trip,
    Experience from,
    Experience to,
  ) {
    final provider = trip == null
        ? null
        : itineraryJourneysProvider(itineraryJourneyKey(trip, from, to));
    final cached = provider != null && ref.exists(provider)
        ? ref.watch(provider).value
        : null;
    final ai = trip == null ? null : activeAiTripSegment(trip, from.id, to.id);
    return _PlanSegment(
      from,
      to,
      ai != null
          ? ai.walkingOnly
          : sharesAccessStop(from.accessStops, to.accessStops) ||
                cached?.walkingOnly == true,
      trip?.transportSelections
          .where((s) => s.from == from.id && s.to == to.id)
          .firstOrNull,
      ai,
    );
  }
  Map? get journey => selection?.data['journey'] as Map?;
  int? get departure => ai?.departureSeconds != null
      ? ai!.departureSeconds! ~/ 60
      : walking
      ? null
      : journey?['departureFromSpotSeconds'] is int
      ? (journey!['departureFromSpotSeconds'] as int) ~/ 60
      : selection?.data['departureMinutes'] as int?;
  int? get arrival => ai?.arrivalSeconds != null
      ? ai!.arrivalSeconds! ~/ 60
      : walking
      ? null
      : journey?['arrivalSeconds'] is int
      ? (journey!['arrivalSeconds'] as int) ~/ 60
      : selection?.data['arrivalMinutes'] == null
      ? null
      : (selection!.data['arrivalMinutes'] as int) +
            (selection!.data['walkingMinutesAfter'] as int? ?? 0);
}

class _SegmentRow extends StatelessWidget {
  final _PlanSegment segment;
  final bool publicTransport;
  final VoidCallback onChoose;
  const _SegmentRow({
    super.key,
    required this.segment,
    required this.publicTransport,
    required this.onChoose,
  });
  @override
  Widget build(BuildContext context) {
    final s = segment;
    final missing =
        publicTransport && !s.walking && s.selection == null && s.ai == null;
    final duration = s.arrival != null && s.departure != null
        ? s.arrival! - s.departure!
        : null;
    final directions = externalDirectionsUri(
      s.from,
      s.to,
      mode: s.walking
          ? DirectionsMode.walking
          : publicTransport
          ? DirectionsMode.transit
          : DirectionsMode.driving,
      platform: defaultTargetPlatform,
      web: kIsWeb,
    );
    final mode = s.walking
        ? '徒歩'
        : publicTransport
        ? '公共交通'
        : '車';
    final title = missing
        ? '交通を選ぶ'
        : '$modeで移動${duration != null && duration >= 0 ? ' · 約$duration分' : ''}';
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: s.selection == null || s.walking
            ? ValueKey('transport-${s.from.id}-${s.to.id}')
            : ValueKey(
                'saved-transport-${s.selection!.data['selectedTripId']}',
              ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 2),
        childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
        minTileHeight: 44,
        leading: Icon(
          s.walking
              ? Icons.directions_walk
              : publicTransport
              ? Icons.directions_bus_outlined
              : Icons.directions_car_outlined,
          size: 20,
          color: AppColors.muted,
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        subtitle: s.ai?.requiresReview == true
            ? const Text(
                '要確認',
                style: TextStyle(fontSize: 11, color: AppColors.primary),
              )
            : null,
        children: [
          if (s.ai != null)
            AiTransportCard(segment: s.ai!)
          else if (s.journey != null)
            TransportJourneyDetails(
              journey: TransportJourney(Map<String, dynamic>.from(s.journey!)),
            )
          else if (s.selection != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.selection!.data['boardingStopName'] ?? '乗車停留所'} ${transportTime(s.departure)} → ${s.selection!.data['alightingStopName'] ?? '降車停留所'} ${transportTime(s.arrival)}',
                  ),
                  if (s.selection!.data['headsign'] is String)
                    Text(
                      transportDirection(
                        s.selection!.data['headsign'] as String,
                      ),
                    ),
                  if (s.selection!.data['walkingMinutesBefore'] != null)
                    Text('乗車前 徒歩${s.selection!.data['walkingMinutesBefore']}分'),
                  if (s.selection!.data['walkingMinutesAfter'] != null)
                    Text('降車後 徒歩${s.selection!.data['walkingMinutesAfter']}分'),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '${s.from.displayName} → ${s.to.displayName}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (missing)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onChoose,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('交通を選択'),
              ),
            ),
          if (directions != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  var opened = false;
                  try {
                    opened = await launchUrl(
                      directions,
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {
                    opened = false;
                  }
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('マップを開けませんでした。時間をおいてお試しください。'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('マップで経路を見る'),
              ),
            ),
        ],
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  final Experience spot;
  final int minutes;
  final VoidCallback onTap;
  const _StopCard({
    super.key,
    required this.spot,
    required this.minutes,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(20),
    elevation: 2,
    shadowColor: AppColors.primary.withValues(alpha: .12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              spot.displayName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 64,
                    child: TravelPhoto(spot),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (spot.category.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.softSurface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            spot.category,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 15,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '約$minutes分',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Endpoint extends StatelessWidget {
  final String name;
  final bool publicTransport;
  const _Endpoint({required this.name, required this.publicTransport});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
    child: Row(
      children: [
        Icon(
          publicTransport
              ? Icons.train_outlined
              : Icons.directions_car_outlined,
          size: 21,
          color: AppColors.muted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  final String? label;
  final bool first, last;
  final Widget child;
  const _TimelineRow({
    this.label,
    this.first = false,
    this.last = false,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 9,
        top: first ? 22 : 0,
        bottom: last ? null : 0,
        height: last ? 22 : null,
        width: 1.5,
        child: const ColoredBox(color: AppColors.accent),
      ),
      if (label != null)
        Positioned(
          left: 5,
          top: 17,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.background,
              border: Border.all(color: AppColors.accent, width: 2),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(left: 26, bottom: 8),
        child: label == null
            ? child
            : MediaQuery.textScalerOf(context).scale(14) > 18 ||
                  MediaQuery.sizeOf(context).width < 350
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: _timeLabel(),
                  ),
                  child,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _timeLabel(),
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
      ),
    ],
  );
  Widget _timeLabel() => Text(
    label!,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  );
}
