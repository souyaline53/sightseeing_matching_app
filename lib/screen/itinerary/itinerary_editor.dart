import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/catalog_data.dart';
import '../../model/experience.dart';
import '../../model/search_settings.dart';
import '../../model/transport.dart';
import '../../repository/transport_repository.dart';
import '../../service/transport/transport_search.dart';
import '../../state/trip_state.dart';
import '../../state/trip_library_state.dart';
import 'add_experience_button.dart';
import 'itinerary_map.dart';
import 'itinerary_spot_card.dart';
import 'itinerary_transport_sheet.dart';

class ItineraryEditor extends ConsumerStatefulWidget {
  const ItineraryEditor({super.key});
  @override
  ConsumerState<ItineraryEditor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<ItineraryEditor> {
  int segment = 0;
  bool collapsed = false;
  double minimumSheet = .22;
  double sheetViewportHeight = 1;
  double headerDragDistance = 0;
  final sheet = DraggableScrollableController();
  @override
  void dispose() {
    sheet.dispose();
    super.dispose();
  }

  void _reorder(int from, int to) {
    if (to == from || to == from + 1) return;
    final hadSelection = ref.read(tripProvider).transportSelections.isNotEmpty;
    ref.read(tripProvider.notifier).reorder(from, to);
    setState(() => segment = 0);
    if (hadSelection) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('訪問順を変更しました。各区間の交通便を再選択してください。')),
      );
    }
  }

  void _sheetTo(double size) {
    if (sheet.isAttached) {
      sheet.animateTo(
        size.clamp(minimumSheet, 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _startHeaderDrag() {
    headerDragDistance = 0;
    if (sheet.isAttached) sheet.jumpTo(sheet.size);
  }

  void _updateHeaderDrag(double delta) {
    if (!sheet.isAttached || sheetViewportHeight <= 0) return;
    headerDragDistance += delta;
    sheet.jumpTo(
      (sheet.size - delta / sheetViewportHeight).clamp(minimumSheet, 1),
    );
  }

  void _endHeaderDrag(double velocity) {
    if (!sheet.isAttached) return;
    final double target;
    if (velocity.abs() >= 350) {
      target = velocity < 0 ? 1 : minimumSheet;
    } else if (headerDragDistance.abs() >= 12) {
      target = headerDragDistance < 0 ? 1 : minimumSheet;
    } else {
      target = sheet.size >= (minimumSheet + 1) / 2 ? 1 : minimumSheet;
    }
    _sheetTo(target);
    headerDragDistance = 0;
  }

  void _cancelHeaderDrag() {
    headerDragDistance = 0;
    _endHeaderDrag(0);
  }

  Future<void> _save() async {
    try {
      ref.read(tripLibraryProvider.notifier).upsert(ref.read(tripProvider));
      await ref.read(tripLibraryProvider.notifier).flush();
      if (ref.read(tripSaveErrorProvider)) throw StateError('save failed');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('旅程を端末に保存しました')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存に失敗しました。再試行してください。')));
      }
    }
  }

  Future<void> _rename() async {
    final trip = ref.read(tripProvider);
    var title = trip.displayTitle;
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('旅のタイトル'),
        content: TextFormField(
          initialValue: title,
          onChanged: (value) => title = value,
          maxLength: 80,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'タイトル'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, title.trim()),
            child: const Text('変更'),
          ),
        ],
      ),
    );
    if (next != null && next.isNotEmpty && mounted) {
      ref
          .read(tripLibraryProvider.notifier)
          .upsert(ref.read(tripProvider).copyWith(title: next));
    }
  }

  Future<void> _stay(Experience spot) async {
    final trip = ref.read(tripProvider);
    final next = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('滞在時間'),
        children: [
          for (final m in {
            30,
            60,
            90,
            120,
            180,
            spot.minutes,
            trip.stayMinutes[spot.id] ?? spot.minutes,
          }.toList()..sort())
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, m),
              child: Text('$m分'),
            ),
        ],
      ),
    );
    if (next != null && mounted) {
      ref.read(tripProvider.notifier).setStay(spot.id, next);
    }
  }

  void _select(TransportCandidate c, Experience from, Experience to) {
    final trip = ref.read(tripProvider);
    ref
        .read(tripProvider.notifier)
        .selectTransport(
          TransportSelection({
            'fromSpotId': from.id,
            'toSpotId': to.id,
            'boardingStopId': c.boarding.stopId,
            'alightingStopId': c.alighting.stopId,
            'boardingSequence': c.boarding.sequence,
            'alightingSequence': c.alighting.sequence,
            'selectedTripId': c.trip.id,
            'transportMode': c.route.data['mode'],
            'walkingMinutesBefore': c.before.walkingMinutes,
            'walkingMinutesAfter': c.after.walkingMinutes,
            'serviceDate': trip.travelDate?.toIso8601String(),
            'verificationStatus': c.status,
            'departureMinutes': c.boarding.departure,
            'arrivalMinutes': c.alighting.arrival,
            'tripVersion': c.trip.data['updatedAt']?.toString(),
          }),
        );
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripProvider);
    final controller = ref.read(tripProvider.notifier);
    final catalog = ref.watch(catalogProvider).value;
    final stops = trip.stops
        .map(
          (e) =>
              catalog?.experiences.where((x) => x.id == e.id).firstOrNull ?? e,
        )
        .toList();
    final index = segment.clamp(0, stops.length > 1 ? stops.length - 2 : 0);
    final from = stops.isEmpty ? null : stops[index];
    final to = stops.length < 2 ? null : stops[index + 1];
    final ids = {
      ...?from?.accessStops.map((s) => s.stopId),
      ...?to?.accessStops.map((s) => s.stopId),
    }.toList()..sort();
    final key = jsonEncode(ids);
    final data = ref.watch(transportDataProvider(key));
    final selected = trip.transportSelections
        .where((s) => s.from == from?.id && s.to == to?.id)
        .firstOrNull;
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, bounds) {
            final compact = bounds.maxHeight < 650;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 12, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.landscape_rounded,
                        color: color.primary,
                        size: 30,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'TABISAKI',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '旅程を保存',
                        onPressed: _save,
                        icon: const Icon(Icons.bookmark_border),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '旅程の操作',
                        onSelected: (value) {
                          if (value == 'title') _rename();
                          if (value == 'map') _sheetTo(.22);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'title', child: Text('タイトルを変更')),
                          PopupMenuItem(value: 'map', child: Text('地図を広く見る')),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          trip.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 21 : 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'タイトルを編集',
                        onPressed: _rename,
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 34),
                      foregroundColor: color.onSurfaceVariant,
                    ),
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: Text(
                      trip.travelDate == null
                          ? '旅行日を選ぶ（未定）'
                          : '${trip.travelDate!.year}/${trip.travelDate!.month}/${trip.travelDate!.day}（${['月', '火', '水', '木', '金', '土', '日'][trip.travelDate!.weekday - 1]}） · ${trip.conditions.length.label}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: trip.travelDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) controller.setDate(date);
                    },
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: color.primary.withValues(alpha: .045),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  margin: const EdgeInsets.fromLTRB(12, 3, 12, 0),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.swap_horiz,
                              color: color.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 5),
                            const Expanded(
                              child: Text(
                                '順番を入れ替える',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            AddExperienceButton(tripId: trip.id, compact: true),
                          ],
                        ),
                      ),
                      if (stops.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            '気になる体験を追加して、\n自分だけの旅を組み立てよう。',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        SizedBox(
                          height: compact ? 142 : 170,
                          child: ReorderableListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(left: 5),
                            itemCount: stops.length,
                            buildDefaultDragHandles: false,
                            onReorder: _reorder,
                            itemBuilder: (context, i) => SizedBox(
                              key: ValueKey(stops[i].id),
                              width: (bounds.maxWidth * .355).clamp(124, 168),
                              child: ItinerarySpotCard(
                                spot: stops[i],
                                index: i,
                                stayMinutes:
                                    trip.stayMinutes[stops[i].id] ??
                                    stops[i].minutes,
                                selected: i == index,
                                first: i == 0,
                                last: i == stops.length - 1,
                                compact: compact,
                                onSelect: () => setState(() => segment = i),
                                onStay: () => _stay(stops[i]),
                                onPrevious: () => _reorder(i, i - 1),
                                onNext: () => _reorder(i, i + 2),
                                onRemove: () => controller.removeStop(stops[i]),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, mapBounds) {
                      sheetViewportHeight = mapBounds.maxHeight;
                      minimumSheet = (76 / mapBounds.maxHeight).clamp(.22, .65);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ItineraryMap(
                            key: const ValueKey('itinerary-map'),
                            origin: trip.origin,
                          ),
                          NotificationListener<DraggableScrollableNotification>(
                            onNotification: (n) {
                              // Keep the footer hidden until the fixed header and save button fit.
                              final next =
                                  n.extent < minimumSheet + .08 ||
                                  n.extent * sheetViewportHeight < 140;
                              if (next != collapsed) {
                                setState(() => collapsed = next);
                              }
                              return false;
                            },
                            child: DraggableScrollableSheet(
                              key: const ValueKey('itinerary-transport-sheet'),
                              controller: sheet,
                              initialChildSize: 1,
                              minChildSize: minimumSheet,
                              maxChildSize: 1,
                              snap: true,
                              snapSizes: [minimumSheet, 1],
                              snapAnimationDuration: const Duration(
                                milliseconds: 250,
                              ),
                              expand: true,
                              builder: (context, scroll) =>
                                  ItineraryTransportSheet(
                                    collapsed: collapsed,
                                    onHeaderDragStart: _startHeaderDrag,
                                    onHeaderDragUpdate: _updateHeaderDrag,
                                    onHeaderDragEnd: _endHeaderDrag,
                                    onHeaderDragCancel: _cancelHeaderDrag,
                                    scrollController: scroll,
                                    from: from,
                                    to: to,
                                    date: trip.travelDate,
                                    selected: selected,
                                    data: data,
                                    index: index,
                                    segmentCount: stops.length > 1
                                        ? stops.length - 1
                                        : 0,
                                    onPrevious: index > 0
                                        ? () => setState(
                                            () => segment = index - 1,
                                          )
                                        : null,
                                    onNext: index < stops.length - 2
                                        ? () => setState(
                                            () => segment = index + 1,
                                          )
                                        : null,
                                    onRefresh: () => ref.invalidate(
                                      transportDataProvider(key),
                                    ),
                                    onSelect: (c) {
                                      if (from != null && to != null) {
                                        _select(c, from, to);
                                      }
                                    },
                                    onClear: selected == null
                                        ? null
                                        : () => controller.clearTransport(
                                            from!.id,
                                            to!.id,
                                          ),
                                    onMap: () => _sheetTo(.22),
                                    onExpand: () => _sheetTo(1),
                                    onSave: _save,
                                  ),
                            ),
                          ),
                        ],
                      );
                    },
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
