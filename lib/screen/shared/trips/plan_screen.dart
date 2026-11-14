import '../../../theme/app_theme.dart';
import '../../../model/ai_trip_segment.dart';
import '../transport/ai_transport_card.dart';
import '../../../state/itinerary_navigation.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/departure_places.dart';
import '../../../service/transport/external_directions.dart';
import '../../../widgets/travel_photo.dart';
import '../experiences/experience_detail.dart';
import '../../../repository/transport_journey_repository.dart';
import '../../../repository/transport_repository.dart';
import '../../../service/transport/itinerary_transport_options.dart';
import '../../../model/transport_journey.dart';
import '../transport/transport_journey_panel.dart';
import '../../../model/stop_selection.dart';
import '../../../data/catalog_data.dart';
import '../../../model/transport.dart';
import '../../../model/search_settings.dart';
import '../../../state/app_tab.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/material.dart';
import '../../../model/experience.dart';
import '../../../state/trip_state.dart';
import '../../../state/trip_library_state.dart';

class PlanScreen extends HookConsumerWidget {
  final String? tripId;
  final List<Experience> stops;
  final String origin;
  final DateTime? date;
  final bool publicTransport, demo;
  final SearchConditions conditions;
  const PlanScreen({
    super.key,
    this.tripId,
    required this.stops,
    required this.origin,
    required this.date,
    required this.publicTransport,
    required this.demo,
    required this.conditions,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref
        .watch(tripLibraryProvider)
        .value
        ?.plans
        .where((p) => p.id == tripId)
        .firstOrNull;
    final livePlan = demo ? null : plan;
    final catalog = ref.watch(catalogProvider).value;
    final stops = (livePlan?.stops ?? this.stops)
        .map(
          (spot) =>
              catalog?.experiences
                  .where((current) => current.id == spot.id)
                  .firstOrNull ??
              spot,
        )
        .toList();
    final origin = livePlan?.origin ?? this.origin;
    final date = livePlan == null ? this.date : livePlan.travelDate;
    final publicTransport = livePlan?.publicTransport ?? this.publicTransport;
    final conditions = livePlan?.conditions ?? this.conditions;
    final originProvider = originTransportStopsProvider(origin);
    final originStops = ref.exists(originProvider)
        ? ref.watch(originProvider).value
        : null;
    final departure = departureNamed(
      origin,
      ref.watch(departurePlacesProvider).value ?? const <DeparturePlace>[],
    );
    final originPoint = Experience(
      livePlan?.originEndpointId ?? TripState.departureEndpointId(origin),
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
      if (tripId != null) {
        ref.read(tripProvider.notifier).openPlan(tripId!);
      }
      if (transportSegment != null) {
        ref
            .read(itineraryTransportRequestProvider.notifier)
            .open(transportSegment);
      }
      ref.read(appTabProvider.notifier).select(AppTab.itinerary);
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    final arrivalName = livePlan?.arrivalPlace ?? origin;
    final arrivalPlace = departureNamed(
      arrivalName,
      ref.watch(departurePlacesProvider).value ?? const <DeparturePlace>[],
    );
    final arrivalPoint = arrivalName == origin
        ? originPoint
        : Experience(
            livePlan?.destinationEndpointId ??
                TripState.departureEndpointId(arrivalName),
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
    final missing = publicTransport
        ? segments
              .where((s) => !s.walking && s.selection == null && s.ai == null)
              .length
        : 0;
    final returning = segments.isEmpty ? null : segments.last.arrival;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text(
          demo ? 'デモ用の旅程' : 'マイプラン',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24),
        ),
      ),
      floatingActionButton: demo
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.soft,
              foregroundColor: _accent,
              elevation: 3,
              onPressed: editPlan,
              icon: const Icon(Icons.route_outlined),
              label: const Text(
                '旅を組み立てる',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              shape: const StadiumBorder(),
            ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            children: [
              Stack(
                children: [
                  const Positioned(
                    right: -15,
                    top: 0,
                    child: SizedBox(
                      width: 185,
                      height: 84,
                      child: CustomPaint(painter: _LandscapePainter()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          date == null
                              ? '旅行日未確定・$origin 発'
                              : '${date.month}月${date.day}日・$origin 発',
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 9),
                        _Metadata(
                          Icons.calendar_today_outlined,
                          '出発時刻 ${transportTime(livePlan?.departureMinutes ?? 480)}',
                        ),
                        const SizedBox(height: 7),
                        _Metadata(
                          Icons.sell_outlined,
                          '${conditions.length.label}・予算${conditions.budget}円以内・${conditions.transport.label}・徒歩${conditions.walking.label}・${conditions.company.label}',
                        ),
                        const SizedBox(height: 5),
                        Padding(
                          padding: const EdgeInsets.only(left: 27),
                          child: Text(
                            '片道${conditions.maxMinutes}分以内',
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (demo)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('デモ用の旅程：AIには接続していません。'),
                ),
              if (missing > 0) ...[
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xffffeeee),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(
                          Icons.report_outlined,
                          color: Color(0xffa83333),
                        ),
                        Text(
                          '未設定の移動が$missing件あります',
                          style: const TextStyle(
                            color: Color(0xffa83333),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (!demo)
                          _ChooseTransport(
                            onTap: () {
                              final index = segments.indexWhere(
                                (s) =>
                                    !s.walking &&
                                    s.selection == null &&
                                    s.ai == null,
                              );
                              editPlan(
                                transportSegment: index == 0
                                    ? -1
                                    : index == stops.length
                                    ? -2
                                    : index - 1,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              _TimelineRow(
                label: '出発',
                first: true,
                child: _EndpointCard(
                  name: origin,
                  subtitle:
                      '出発 ${transportTime(livePlan?.departureMinutes ?? 480)}',
                  publicTransport: publicTransport,
                ),
              ),
              for (var i = 0; i < stops.length; i++) ...[
                _TimelineRow(
                  child: _SegmentRow(
                    segment: segments[i],
                    publicTransport: publicTransport,
                    onChoose: demo
                        ? null
                        : () => editPlan(transportSegment: i == 0 ? -1 : i - 1),
                  ),
                ),
                _TimelineRow(
                  label: '${i + 1}',
                  child: _TripCard(
                    onTap: () => showExperience(context, stops[i]),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(13),
                              child: TravelPhoto(stops[i]),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stops[i].displayName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${stops[i].area}・滞在${livePlan?.stayMinutes[stops[i].id] ?? stops[i].minutes}分',
                                  style: const TextStyle(color: _muted),
                                ),
                                if (segments[i].arrival != null) ...[
                                  const SizedBox(height: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.softSurface,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '◷ ${transportTime(segments[i].arrival)} 着'
                                      '${segments[i + 1].departure == null ? '' : ' / ${transportTime(segments[i + 1].departure)} 発'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: _muted,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (stops.isNotEmpty) ...[
                _TimelineRow(
                  child: _SegmentRow(
                    segment: segments.last,
                    publicTransport: publicTransport,
                    returning: true,
                    onChoose: demo
                        ? null
                        : () => editPlan(transportSegment: -2),
                  ),
                ),
                _TimelineRow(
                  label: '帰着',
                  last: true,
                  child: _EndpointCard(
                    name: arrivalName,
                    publicTransport: publicTransport,
                    subtitle: returning == null
                        ? '到着時刻未定'
                        : '${transportTime(returning)} 着',
                  ),
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '訪問先を追加して、旅を組み立てましょう。',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _accent = AppColors.primary;
const _muted = AppColors.muted;

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
  final bool publicTransport, returning;
  final VoidCallback? onChoose;
  const _SegmentRow({
    required this.segment,
    required this.publicTransport,
    this.returning = false,
    this.onChoose,
  });
  @override
  Widget build(BuildContext context) {
    final s = segment;
    if (s.ai != null) return AiTransportCard(segment: s.ai!);
    final missing =
        publicTransport && !s.walking && s.selection == null && s.ai == null;
    final duration = s.arrival != null && s.departure != null
        ? s.arrival! - s.departure!
        : null;
    final legs = s.journey?['legs'] as List?;
    final route = legs
        ?.map((l) => l['routeName'])
        .whereType<String>()
        .join(' → ');
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
    return InkWell(
      key: s.selection == null || s.walking
          ? null
          : ValueKey('saved-transport-${s.selection!.data['selectedTripId']}'),
      borderRadius: BorderRadius.circular(12),
      onTap: missing
          ? onChoose
          : s.selection == null
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (context) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: s.journey != null
                    ? TransportJourneyDetails(
                        journey: TransportJourney(
                          Map<String, dynamic>.from(s.journey!),
                        ),
                      )
                    : Text(
                        '${s.selection!.data['boardingStopName'] ?? '乗車停留所'} ${transportTime(s.departure)} → ${s.selection!.data['alightingStopName'] ?? '降車停留所'} ${transportTime(s.arrival)}\n${s.selection!.data['headsign'] == null ? '' : transportDirection(s.selection!.data['headsign'] as String)}\n乗車前 徒歩${s.selection!.data['walkingMinutesBefore'] ?? '未登録'}分・降車後 徒歩${s.selection!.data['walkingMinutesAfter'] ?? '未登録'}分',
                      ),
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              missing
                  ? Icons.warning_amber_rounded
                  : s.walking
                  ? Icons.directions_walk
                  : publicTransport
                  ? Icons.directions_bus_outlined
                  : Icons.directions_car_outlined,
              color: missing ? const Color(0xffdd5b14) : _accent,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 5,
                    children: [
                      Text(
                        missing
                            ? '移動手段が未設定'
                            : s.walking
                            ? '徒歩のみ'
                            : returning
                            ? '帰路'
                            : publicTransport
                            ? '公共交通で移動'
                            : '車で移動',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: missing ? const Color(0xffd9540c) : null,
                        ),
                      ),
                      if (!missing && !s.walking && duration != null)
                        Text(
                          '$duration分',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    missing
                        ? '${s.from.displayName} → ${s.to.displayName}'
                        : route?.isNotEmpty == true
                        ? route!
                        : s.walking
                        ? '共通の最寄り停留所間'
                        : '所要時間・費用は未登録です',
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                  if (!missing &&
                      !s.walking &&
                      s.departure != null &&
                      s.arrival != null)
                    Text(
                      '${transportTime(s.departure)} → ${transportTime(s.arrival)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  TextButton.icon(
                    onPressed: directions == null
                        ? null
                        : () async {
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
                    style: TextButton.styleFrom(
                      foregroundColor: _accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 6,
                      ),
                      alignment: Alignment.centerLeft,
                    ),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(
                      directions == null ? '位置情報未登録' : 'マップで経路を見る',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            if (missing && onChoose != null)
              IconButton(
                tooltip: '交通を選択',
                onPressed: onChoose,
                icon: const Icon(Icons.chevron_right, color: _accent),
              ),
            if (s.selection != null && !s.walking)
              const Icon(Icons.expand_more, color: _muted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _TripCard({required this.child, this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(16),
    child: Ink(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.softSurface, AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12a64708),
            offset: Offset(0, 2),
            blurRadius: 3,
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
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
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 43,
          child: Column(
            children: [
              SizedBox(
                height: 12,
                child: first
                    ? null
                    : const VerticalDivider(
                        width: 2,
                        thickness: 1.5,
                        color: AppColors.accent,
                      ),
              ),
              if (label != null)
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: first || last ? _accent : AppColors.soft,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    label!,
                    style: TextStyle(
                      color: first || last ? Colors.white : _accent,
                      fontSize: first || last ? 12 : 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent, width: 2),
                  ),
                ),
              Expanded(
                child: last
                    ? const SizedBox()
                    : const VerticalDivider(
                        width: 2,
                        thickness: 1.5,
                        color: AppColors.accent,
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [child, const SizedBox(height: 16)],
          ),
        ),
      ],
    ),
  );
}

class _EndpointCard extends StatelessWidget {
  final String name, subtitle;
  final bool publicTransport;
  const _EndpointCard({
    required this.name,
    required this.subtitle,
    required this.publicTransport,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            publicTransport
                ? Icons.train_outlined
                : Icons.directions_car_outlined,
            color: _accent,
            size: 29,
          ),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(subtitle, style: const TextStyle(color: _muted)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Metadata extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Metadata(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: _muted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: const TextStyle(fontSize: 14, height: 1.5)),
      ),
    ],
  );
}

class _ChooseTransport extends StatelessWidget {
  final VoidCallback onTap;
  const _ChooseTransport({required this.onTap});
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: _accent,
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.border),
      visualDensity: VisualDensity.compact,
    ),
    child: const Text('交通を選択 ›', style: TextStyle(fontWeight: FontWeight.w700)),
  );
}

class _LandscapePainter extends CustomPainter {
  const _LandscapePainter();
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final y = size.height * (.35 + i * .18);
      final path = Path()
        ..moveTo(0, size.height)
        ..lineTo(0, y + 18)
        ..cubicTo(
          size.width * .3,
          y - 24,
          size.width * .5,
          y + 28,
          size.width * .7,
          y,
        )
        ..quadraticBezierTo(size.width * .9, y - 25, size.width, y - 10)
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = AppColors.accent.withValues(alpha: .15 + i * .08),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LandscapePainter oldDelegate) => false;
}
