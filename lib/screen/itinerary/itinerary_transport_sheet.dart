import '../../service/transport/itinerary_transport_options.dart';
import '../../model/transport_journey.dart';
import 'transport_journey_panel.dart';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../model/experience.dart';
import '../../model/transport.dart';
import '../../repository/transport_repository.dart';
import '../../service/transport/transport_search.dart';
import 'transport_timetable.dart';

class ItineraryTransportSheet extends StatelessWidget {
  final ScrollController scrollController;
  final Experience? from, to;
  final DateTime? date;
  final TransportSelection? selected;
  final AsyncValue<TransportData> data;
  final AsyncValue<JourneySearchResult>? journeys;
  final int earliestDepartureSeconds;
  final int index, segmentCount;
  final bool collapsed;
  final VoidCallback? onPrevious, onNext, onClear;
  final VoidCallback onRefresh, onMap, onExpand;
  final ValueChanged<TransportCandidate> onSelect;
  final VoidCallback onHeaderDragStart, onHeaderDragCancel;
  final ValueChanged<double> onHeaderDragUpdate, onHeaderDragEnd;
  const ItineraryTransportSheet({
    super.key,
    required this.scrollController,
    required this.from,
    required this.to,
    required this.date,
    required this.selected,
    required this.data,
    this.journeys,
    this.earliestDepartureSeconds = 8 * 3600,
    required this.index,
    required this.segmentCount,
    required this.onPrevious,
    required this.onNext,
    required this.onClear,
    required this.onRefresh,
    required this.onMap,
    required this.onExpand,
    required this.onSelect,
    required this.onHeaderDragStart,
    required this.onHeaderDragUpdate,
    required this.onHeaderDragEnd,
    required this.onHeaderDragCancel,
    this.collapsed = false,
  });
  bool matches(TransportCandidate c) =>
      c.journey != null && selected?.data['journey'] is Map
      ? c.journey!.id == (selected!.data['journey'] as Map)['id']
      : selected != null &&
            c.trip.id == selected!.data['selectedTripId'] &&
            c.boarding.stopId == selected!.data['boardingStopId'] &&
            c.alighting.stopId == selected!.data['alightingStopId'] &&
            c.boarding.sequence == selected!.data['boardingSequence'] &&
            c.alighting.sequence == selected!.data['alightingSequence'] &&
            c.boarding.departure == selected!.data['departureMinutes'] &&
            c.alighting.arrival == selected!.data['arrivalMinutes'] &&
            (c.trip.data['versionId'] ?? c.trip.data['updatedAt'])
                    ?.toString() ==
                selected!.data['tripVersion'];
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: BottomSheet(
        enableDrag: false,
        onClosing: () {},
        backgroundColor: Colors.white,
        elevation: 16,
        shadowColor: Colors.black26,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        clipBehavior: Clip.antiAlias,
        builder: (context) => Column(
          children: [
            Semantics(
              label: '交通情報シートの操作',
              hint: '上にスワイプして展開、下にスワイプして閉じる',
              onIncrease: onExpand,
              onDecrease: onMap,
              child: GestureDetector(
                key: const ValueKey('transport-sheet-header'),
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => onHeaderDragStart(),
                onVerticalDragUpdate: (details) =>
                    onHeaderDragUpdate(details.delta.dy),
                onVerticalDragEnd: (details) =>
                    onHeaderDragEnd(details.primaryVelocity ?? 0),
                onVerticalDragCancel: onHeaderDragCancel,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 9),
                          decoration: BoxDecoration(
                            color: color.outlineVariant,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.directions_transit_outlined,
                            color: color.primary,
                            size: 23,
                          ),
                          const SizedBox(width: 7),
                          const Expanded(
                            child: Text(
                              '交通情報',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (!collapsed)
                            TextButton.icon(
                              onPressed: onRefresh,
                              style: TextButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                side: BorderSide(color: color.outlineVariant),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                minimumSize: const Size(0, 30),
                              ),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text(
                                '情報を更新',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                key: const ValueKey('transport-sheet-scroll'),
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                children: [
                  if (!collapsed) ...[
                    if (to == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('体験を追加し、出発地または観光地のカードを選ぶと交通情報を確認できます。'),
                      )
                    else ...[
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              from!.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              Icons.east,
                              color: color.primary,
                              size: 19,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              to!.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),
                      Text(
                        date == null
                            ? '日程未選択：時刻表は参考情報です。'
                            : '${date!.year}/${date!.month}/${date!.day} の時刻表',
                        style: TextStyle(
                          fontSize: 11,
                          color: color.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _results(context),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onExpand,
                            icon: const Icon(Icons.compare_arrows, size: 20),
                            label: const Text(
                              '候補を比較',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              minimumSize: const Size(0, 43),
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const ValueKey('itinerary-show-map'),
                            onPressed: onMap,
                            icon: const Icon(Icons.map_outlined, size: 20),
                            label: const Text(
                              '地図で見る',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              minimumSize: const Size(0, 43),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final d = data.value ?? TransportData([], [], [], [], []);
    final local = findCandidates(
      trips: d.trips,
      routes: d.routes,
      services: d.services,
      fares: d.fares,
      stops: d.stops,
      from: from!.accessStops,
      to: to!.accessStops,
      date: date,
    );
    String identity(TransportCandidate c) =>
        '${c.trip.id}:${c.boarding.sequence}:${c.alighting.sequence}:${c.boarding.departure}';
    final merged = {for (final c in local) identity(c): c};
    for (final journey in journeys?.value?.journeys ?? <TransportJourney>[]) {
      var c = journeyCandidate(journey);
      final existing = merged[identity(c)];
      if (existing != null) {
        c = TransportCandidate(
          existing.trip,
          existing.route,
          existing.before,
          existing.after,
          existing.boarding,
          existing.alighting,
          existing.fare,
          journey: journey,
          boardingStopName: existing.boardingStopName,
          alightingStopName: existing.alightingStopName,
        );
      }
      merged[identity(c)] = c;
    }
    final candidates =
        merged.values
            .where(
              (c) => candidateDepartureSeconds(c) >= earliestDepartureSeconds,
            )
            .toList()
          ..sort(
            (a, b) =>
                (a.boarding.data['departureSeconds'] as int? ??
                        a.boarding.departure! * 60)
                    .compareTo(
                      b.boarding.data['departureSeconds'] as int? ??
                          b.boarding.departure! * 60,
                    ),
          );
    final hasSelected = candidates.any(matches);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.isLoading || journeys?.isLoading == true)
          const Padding(
            padding: EdgeInsets.all(14),
            child: LinearProgressIndicator(),
          ),
        if (data.hasError && (journeys == null || journeys!.hasError))
          const _Notice('交通情報を取得できませんでした。情報を更新して再試行できます。編集・保存は続けられます。'),
        if (selected != null &&
            !candidates.any(matches) &&
            !data.isLoading &&
            journeys?.isLoading != true)
          const _Notice('保存した便は現在の候補に含まれていません。別の便を選択できます。'),
        if (candidates.isEmpty &&
            !data.isLoading &&
            journeys?.isLoading != true)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              from!.accessStops.isEmpty || to!.accessStops.isEmpty
                  ? '最寄り駅・バス停が未登録です。\nこの区間の交通情報は未登録です。'
                  : 'この時刻以降の候補がありません。',
            ),
          ),
        for (var i = 0; i < candidates.length; i++)
          _candidate(
            context,
            candidates[i],
            d,
            featured: matches(candidates[i]) || (!hasSelected && i == 0),
          ),
      ],
    );
  }

  Widget _candidate(
    BuildContext context,
    TransportCandidate c,
    TransportData d, {
    required bool featured,
  }) {
    final color = Theme.of(context).colorScheme;
    final chosen = matches(c);
    final time =
        '${transportTime(c.boarding.departure)} → ${transportTime(c.alighting.arrival)}';
    final chooseKey = ValueKey(
      'choose-${c.trip.id}-${c.boarding.sequence}-${c.alighting.sequence}',
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (featured)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    chosen ? '選択した便' : '時刻表を見て選ぶ',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color.primary,
                    ),
                  ),
                ),
                const Spacer(),
                if (c.status == 'sample')
                  const Text('サンプル', style: TextStyle(fontSize: 10)),
              ],
            ),
          ),
        Row(
          children: [
            if (!featured)
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: Icon(
                  chosen ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18,
                  color: color.outline,
                ),
              ),
            Expanded(
              flex: 5,
              child: Text(
                time,
                style: TextStyle(
                  fontWeight: featured ? FontWeight.w800 : FontWeight.w600,
                  fontSize: featured ? 16 : 13,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.route.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (c.trip.data['headsign'] is String)
                    Text(
                      c.trip.data['headsign'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: color.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              c.fare == null ? '運賃\n未確認' : '¥${c.fare}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        if (featured) ...[
          const SizedBox(height: 7),
          Row(
            children: [
              if (c.before.walkingMinutes != null ||
                  c.after.walkingMinutes != null)
                Icon(Icons.directions_walk, size: 15, color: color.primary),
              Expanded(
                child: Text(
                  [
                    if (c.before.walkingMinutes != null)
                      '乗車前 徒歩${c.before.walkingMinutes}分',
                    if (c.after.walkingMinutes != null)
                      '降車後 徒歩${c.after.walkingMinutes}分',
                  ].join(' ＋ '),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              FilledButton(
                onPressed: () => onSelect(c),
                key: chooseKey,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(
                  chosen ? '選択中' : 'この便で行く',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => _details(context, c, d),
            style: TextButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: const Size(0, 26),
              padding: EdgeInsets.zero,
            ),
            child: const Text('時刻表・アクセスを見る', style: TextStyle(fontSize: 11)),
          ),
        ] else
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: '時刻表・アクセスを見る',
              onPressed: () => _details(context, c, d),
              icon: const Icon(Icons.keyboard_arrow_right, size: 17),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 18),
            ),
          ),
      ],
    );
    return Container(
      key: ValueKey(
        'candidate-${c.trip.id}-${c.boarding.sequence}-${c.alighting.sequence}',
      ),
      margin: EdgeInsets.only(bottom: featured ? 4 : 0),
      decoration: BoxDecoration(
        color: featured ? color.primary.withValues(alpha: .055) : Colors.white,
        borderRadius: BorderRadius.circular(featured ? 15 : 5),
        border: featured
            ? Border.all(color: color.primary, width: 1.5)
            : Border(
                bottom: BorderSide(
                  color: color.outlineVariant.withValues(alpha: .5),
                ),
              ),
      ),
      child: InkWell(
        key: featured ? null : chooseKey,
        onTap: () => onSelect(c),
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: featured ? 9 : 7,
          ),
          child: content,
        ),
      ),
    );
  }

  void _details(BuildContext context, TransportCandidate c, TransportData d) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => FractionallySizedBox(
        heightFactor: .88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 8, 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.route.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '時刻表を閉じる',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                children: [
                  if (c.status == 'sample') Text(verificationLabel(c.status)),
                  const SizedBox(height: 12),
                  if (c.journey != null)
                    TransportJourneyDetails(journey: c.journey!)
                  else
                    Text(
                      [
                        from!.displayName,
                        if (c.before.walkingMinutes != null)
                          '↓ 徒歩${c.before.walkingMinutes}分',
                        '${c.boardingLabel(c.boardingStopName ?? '乗車停留所')} ${transportTime(c.boarding.departure)} 発',
                        '↓ ${c.route.name}',
                        '${c.alightingStopName ?? '降車停留所'} ${transportTime(c.alighting.arrival)} 着',
                        if (c.after.walkingMinutes != null)
                          '↓ 徒歩${c.after.walkingMinutes}分',
                        to!.displayName,
                      ].join('\n'),
                      style: const TextStyle(height: 1.8),
                    ),
                  Text(c.fare == null ? '運賃未確認' : '大人運賃 ¥${c.fare}'),
                  if (c.trip.data['sourceCheckedAt'] != null)
                    Text('情報確認日：${c.trip.data['sourceCheckedAt']}'),
                  for (final record in [c.route, c.trip])
                    if (record.data['sourceUrl'] is String &&
                        (record.data['sourceUrl'] as String).startsWith('http'))
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse(record.data['sourceUrl'] as String),
                        ),
                        child: const Text('情報源を見る'),
                      ),
                  if (c.journey == null ||
                      c.journey!.legs.length == 1 && c.trip.times.length > 2)
                    TransportTimetable(
                      trip: c.trip,
                      data: d,
                      initiallyExpanded: true,
                    ),
                  const SizedBox(height: 15),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      onSelect(c);
                      Navigator.pop(context);
                    },
                    child: const Text('この便で行く'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice(this.text);
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.primary.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: color.primary),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 10,
                color: color.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
