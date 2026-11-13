import 'ai_trip_panel.dart';
import '../../state/itinerary_navigation.dart';
import '../../widgets/find_experiences_button.dart';
import '../../state/app_tab.dart';
import '../../state/discovery_state.dart';
import '../../state/settings_state.dart';
import '../home/trips_drawer.dart';
import '../../repository/transport_journey_repository.dart';
import '../../service/transport/itinerary_transport_options.dart';
import 'itinerary_endpoint_card.dart';
import 'plan_screen.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  double middleSheet = .6;
  double sheetViewportHeight = 1;
  double headerDragDistance = 0;
  final sheet = DraggableScrollableController();
  final mapSheetChanges = ValueNotifier<int>(0);
  bool sheetUpdateQueued = false;
  @override
  void initState() {
    super.initState();
    sheet.addListener(_queueSheetUpdate);
  }

  // Sheet constraints can notify during layout. Update the map after that frame.
  void _queueSheetUpdate() {
    if (sheetUpdateQueued) return;
    sheetUpdateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sheetUpdateQueued = false;
      if (!mounted || !sheet.isAttached) return;
      mapSheetChanges.value++;
      final next = sheet.size < minimumSheet + .08;
      if (next != collapsed) setState(() => collapsed = next);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    sheet.removeListener(_queueSheetUpdate);
    mapSheetChanges.dispose();
    sheet.dispose();
    super.dispose();
  }

  void _searchExperiences() {
    final settings = ref.read(settingsProvider).requireValue;
    ref.read(searchDraftProvider.notifier).replace(settings.profile.defaults());
    ref.read(discoveryProvider.notifier).beginSearch();
    ref.read(appTabProvider.notifier).select(AppTab.recommendation);
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
    final stops = [minimumSheet, middleSheet, 1.0];
    final double target;
    if (velocity.abs() >= 350) {
      target = velocity < 0
          ? stops.firstWhere((size) => size > sheet.size + .02, orElse: () => 1)
          : stops.lastWhere(
              (size) => size < sheet.size - .02,
              orElse: () => minimumSheet,
            );
    } else {
      target = stops.reduce(
        (a, b) => (a - sheet.size).abs() <= (b - sheet.size).abs() ? a : b,
      );
    }
    _sheetTo(target);
    headerDragDistance = 0;
  }

  void _cancelHeaderDrag() {
    headerDragDistance = 0;
    _endHeaderDrag(0);
  }

  void _openBooklet() {
    final trip = ref.read(tripProvider);
    if (trip.stops.isEmpty) return;
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
    if (c.journey != null) {
      ref
          .read(tripProvider.notifier)
          .selectTransport(
            c.journey!.selection(
              from.id,
              to.id,
              originName: from.id == trip.originEndpointId
                  ? trip.origin
                  : to.id == trip.destinationEndpointId
                  ? trip.arrivalPlace
                  : null,
              fromOrigin: from.id == trip.originEndpointId,
              toOrigin: to.id == trip.destinationEndpointId,
            ),
          );
      return;
    }
    ref
        .read(tripProvider.notifier)
        .selectTransport(
          TransportSelection({
            'fromSpotId': from.id,
            'fromKind': from.id == trip.originEndpointId ? 'origin' : 'spot',
            'toKind': to.id == trip.destinationEndpointId ? 'origin' : 'spot',
            if (from.id == trip.originEndpointId ||
                to.id == trip.destinationEndpointId)
              'originName': from.id == trip.originEndpointId
                  ? trip.origin
                  : trip.arrivalPlace,
            'toSpotId': to.id,
            'boardingStopId': c.boarding.stopId,
            'boardingStopName': c.boardingStopName ?? c.before.data['stopName'],
            'alightingStopName':
                c.alightingStopName ?? c.after.data['stopName'],
            'headsign': c.trip.data['headsign'],
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
            'tripVersion':
                (c.trip.data['versionId'] ?? c.trip.data['updatedAt'])
                    ?.toString(),
            'feedId': c.trip.data['feedId'],
            'departureSeconds': c.boarding.data['departureSeconds'],
            'arrivalSeconds': c.alighting.data['arrivalSeconds'],
          }),
        );
  }

  @override
  Widget build(BuildContext context) {
    final transportRequest = ref.watch(itineraryTransportRequestProvider);
    if (transportRequest != null) {
      segment = transportRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !sheet.isAttached ||
            ref.read(itineraryTransportRequestProvider) != transportRequest) {
          return;
        }
        ref.read(itineraryTransportRequestProvider.notifier).clear();
        _sheetTo(1);
      });
    }
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
    final originSelected = segment == -1;
    final returnSelected = segment == -2;
    final endpointSelected = originSelected || returnSelected;
    final originProvider = originTransportStopsProvider(trip.origin);
    final originStops =
        stops.isNotEmpty && (endpointSelected || ref.exists(originProvider))
        ? ref.watch(originProvider)
        : const AsyncData<List<TransportStop>>([]);
    final arrivalProvider = originTransportStopsProvider(trip.arrivalPlace);
    final arrivalStops = trip.arrivalPlace == trip.origin
        ? originStops
        : stops.isNotEmpty && (returnSelected || ref.exists(arrivalProvider))
        ? ref.watch(arrivalProvider)
        : const AsyncData<List<TransportStop>>([]);
    final endpointStops = returnSelected ? arrivalStops : originStops;
    // View-only endpoints never enter the sightseeing list.
    final origin = Experience(
      trip.originEndpointId,
      trip.origin,
      '',
      '',
      '',
      '',
      '',
      '',
      0,
      name: trip.origin,
      accessStops: [
        for (final stop in originStops.value ?? <TransportStop>[])
          AccessStop({
            'walkingMinutes': null,
            'sourceType': stop.data['sourceType'] ?? 'manual',
            'verificationStatus':
                stop.data['verificationStatus'] ?? 'unverified',
            ...stop.data,
            'stopId': stop.id,
          }),
      ],
    );
    final destination = Experience(
      trip.destinationEndpointId,
      trip.arrivalPlace,
      '',
      '',
      '',
      '',
      '',
      '',
      0,
      name: trip.arrivalPlace,
      accessStops: [
        for (final stop in arrivalStops.value ?? <TransportStop>[])
          AccessStop({'walkingMinutes': null, ...stop.data, 'stopId': stop.id}),
      ],
    );
    final from = returnSelected
        ? stops.lastOrNull
        : originSelected
        ? origin
        : stops.isEmpty
        ? null
        : stops[index];
    final to = returnSelected
        ? (stops.isEmpty ? null : destination)
        : originSelected
        ? stops.firstOrNull
        : stops.length < 2
        ? null
        : stops[index + 1];
    final ids = {
      ...?from?.accessStops.map((s) => s.stopId),
      ...?to?.accessStops.map((s) => s.stopId),
    }.toList()..sort();
    final key = jsonEncode(ids);
    final walkingOnly = sharesAccessStop(
      from?.accessStops ?? [],
      to?.accessStops ?? [],
    );
    final AsyncValue<TransportData> data;
    if (walkingOnly) {
      data = AsyncData(TransportData([], [], [], [], []));
    } else if (endpointSelected && endpointStops.isLoading) {
      data = const AsyncLoading();
    } else if (endpointSelected && endpointStops.hasError) {
      data = AsyncError(
        endpointStops.error!,
        endpointStops.stackTrace ?? StackTrace.empty,
      );
    } else {
      data = ref.watch(transportDataProvider(key));
    }
    final journeyKey = itineraryJourneyKey(trip, from, to);
    final journeys =
        !walkingOnly &&
            from != null &&
            to != null &&
            from.accessStops.isNotEmpty &&
            to.accessStops.isNotEmpty
        ? ref.watch(itineraryJourneysProvider(journeyKey))
        : null;
    final previousIndex = stops.indexWhere((s) => s.id == from?.id);
    final previousPoint = previousIndex == 0
        ? origin
        : previousIndex > 0
        ? stops[previousIndex - 1]
        : null;
    final previousPool = itineraryJourneysProvider(
      itineraryJourneyKey(trip, previousPoint, from),
    );
    final cachedPreviousWalking = ref.exists(previousPool)
        ? ref.watch(previousPool).value?.walkingOnly == true
        : false;
    final previousWalkingOnly =
        sharesAccessStop(
          previousPoint?.accessStops ?? [],
          from?.accessStops ?? [],
        ) ||
        cachedPreviousWalking;
    final earliestDepartureSeconds = segmentEarliestDeparture(
      trip,
      from?.id,
      previousWalkingOnly: previousWalkingOnly,
    );
    final selected = trip.transportSelections
        .where((s) => s.from == from?.id && s.to == to?.id)
        .firstOrNull;
    final color = Theme.of(context).colorScheme;
    final isEmpty = trip.saved.isEmpty && trip.stops.isEmpty;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: '旅の一覧を開く',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu),
          ),
        ),
        title: const Text('旅程作成', style: TextStyle(fontSize: 22)),
        actions: isEmpty
            ? null
            : [
                TextButton.icon(
                  key: const ValueKey('itinerary-view-booklet'),
                  onPressed: trip.stops.isEmpty ? null : _openBooklet,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    textStyle: Theme.of(context).textTheme.labelMedium,
                  ),
                  icon: const Icon(Icons.menu_book_outlined, size: 16),
                  label: const Text('しおりを見る'),
                ),
                PopupMenuButton<String>(
                  tooltip: '旅程の操作',
                  onSelected: (value) {
                    if (value == 'title') _rename();
                    if (value == 'map') _sheetTo(minimumSheet);
                    if (value == 'ai_saved') {
                      ref.read(aiRestoreIntentProvider.notifier).open();
                    }
                    if (value == 'ai_refresh') {
                      ref.read(aiRefreshIntentProvider.notifier).open();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'title', child: Text('タイトルを変更')),
                    PopupMenuItem(value: 'map', child: Text('地図を広く見る')),
                    PopupMenuItem(
                      value: 'ai_saved',
                      child: Text('保存したAIの旅を開く'),
                    ),
                    PopupMenuItem(
                      value: 'ai_refresh',
                      child: Text('AIの保存済み結果を確認'),
                    ),
                  ],
                ),
              ],
      ),
      drawer: TripsDrawer(onNewTrip: _searchExperiences),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            excluding: isEmpty,
            child: IgnorePointer(
              ignoring: isEmpty,
              child: SafeArea(
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    final compact = bounds.maxHeight < 650;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: bounds.maxHeight * .6,
                          ),
                          child: SingleChildScrollView(
                            key: const ValueKey('itinerary-scroll'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    14,
                                    0,
                                  ),
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
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        alignment: Alignment.centerLeft,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        minimumSize: const Size(0, 34),
                                        foregroundColor: color.onSurfaceVariant,
                                      ),
                                      icon: const Icon(
                                        Icons.calendar_month_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        trip.travelDate == null
                                            ? '出発日未設定'
                                            : '${trip.travelDate!.year}/${trip.travelDate!.month}/${trip.travelDate!.day}（${['月', '火', '水', '木', '金', '土', '日'][trip.travelDate!.weekday - 1]}） · ${trip.conditions.length.label}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      onPressed: null,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        OutlinedButton.icon(
                                          key: const ValueKey(
                                            'itinerary-departure-time',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            alignment: Alignment.centerLeft,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                            ),
                                            minimumSize: const Size(0, 34),
                                            foregroundColor:
                                                color.onSurfaceVariant,
                                          ),
                                          icon: const Icon(
                                            Icons.schedule,
                                            size: 18,
                                          ),
                                          label: Text(
                                            '出発時刻 ${transportTime(trip.departureMinutes)}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                            ),
                                          ),
                                          onPressed: () async {
                                            final time = await showTimePicker(
                                              initialEntryMode:
                                                  TimePickerEntryMode.input,
                                              context: context,
                                              initialTime: TimeOfDay(
                                                hour:
                                                    trip.departureMinutes ~/ 60,
                                                minute:
                                                    trip.departureMinutes % 60,
                                              ),
                                            );
                                            if (time != null) {
                                              controller.setDepartureMinutes(
                                                time.hour * 60 + time.minute,
                                              );
                                            }
                                          },
                                        ),
                                        const AiTripPanel(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, mapBounds) {
                              sheetViewportHeight = mapBounds.maxHeight;
                              final cardsHeight = ((compact ? 142 : 170) + 66.0)
                                  .clamp(0.0, mapBounds.maxHeight * .55);
                              final mapHeight =
                                  mapBounds.maxHeight - cardsHeight;
                              middleSheet = mapHeight / mapBounds.maxHeight;
                              minimumSheet = (76 / mapBounds.maxHeight).clamp(
                                .1,
                                middleSheet * .8,
                              );
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  Column(
                                    children: [
                                      SizedBox(
                                        height: cardsHeight,
                                        child: SingleChildScrollView(
                                          child: Column(
                                            children: [
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: color.primary
                                                      .withValues(alpha: .045),
                                                  borderRadius:
                                                      const BorderRadius.vertical(
                                                        top: Radius.circular(
                                                          20,
                                                        ),
                                                      ),
                                                ),
                                                margin:
                                                    const EdgeInsets.fromLTRB(
                                                      12,
                                                      3,
                                                      12,
                                                      0,
                                                    ),
                                                child: Column(
                                                  children: [
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.fromLTRB(
                                                            10,
                                                            0,
                                                            4,
                                                            0,
                                                          ),
                                                      child: Row(
                                                        children: [
                                                          /*Icon(
                              Icons.swap_horiz,
                              color: color.primary,
                              size: 18,
                            ),*/
                                                          const SizedBox(
                                                            width: 5,
                                                          ),
                                                          const Expanded(
                                                            child: Text(
                                                              '',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                          AddExperienceButton(
                                                            tripId: trip.id,
                                                            compact: true,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      height: compact
                                                          ? 142
                                                          : 170,
                                                      child: ReorderableListView.builder(
                                                        scrollDirection:
                                                            Axis.horizontal,
                                                        padding:
                                                            const EdgeInsets.only(
                                                              left: 5,
                                                            ),
                                                        header: SizedBox(
                                                          width: 105,
                                                          child: ItineraryEndpointCard(
                                                            key: const ValueKey(
                                                              'itinerary-departure',
                                                            ),
                                                            departure: true,
                                                            label: trip.origin,
                                                            selected:
                                                                originSelected,
                                                            onTap: () {
                                                              setState(
                                                                () => segment =
                                                                    -1,
                                                              );
                                                              _sheetTo(1);
                                                            },
                                                          ),
                                                        ),
                                                        footer: SizedBox(
                                                          width: 85,
                                                          child: ItineraryEndpointCard(
                                                            key: const ValueKey(
                                                              'itinerary-home',
                                                            ),
                                                            departure: false,
                                                            label: trip
                                                                .arrivalPlace,
                                                          ),
                                                        ),
                                                        itemCount: stops.length,
                                                        buildDefaultDragHandles:
                                                            false,
                                                        onReorder: _reorder,
                                                        itemBuilder: (context, i) => SizedBox(
                                                          key: ValueKey(
                                                            stops[i].id,
                                                          ),
                                                          width:
                                                              (bounds.maxWidth *
                                                                      .355)
                                                                  .clamp(
                                                                    124,
                                                                    168,
                                                                  ),
                                                          child: ItinerarySpotCard(
                                                            spot: stops[i],
                                                            index: i,
                                                            stayMinutes:
                                                                trip.stayMinutes[stops[i]
                                                                    .id] ??
                                                                stops[i]
                                                                    .minutes,
                                                            selected:
                                                                !originSelected &&
                                                                (returnSelected
                                                                    ? i ==
                                                                          stops.length -
                                                                              1
                                                                    : i ==
                                                                          index),
                                                            first: i == 0,
                                                            last:
                                                                i ==
                                                                stops.length -
                                                                    1,
                                                            compact: compact,
                                                            onSelect: () => setState(
                                                              () => segment =
                                                                  i ==
                                                                      stops.length -
                                                                          1
                                                                  ? -2
                                                                  : i,
                                                            ),
                                                            onStay: () =>
                                                                _stay(stops[i]),
                                                            onPrevious: () =>
                                                                _reorder(
                                                                  i,
                                                                  i - 1,
                                                                ),
                                                            onNext: () =>
                                                                _reorder(
                                                                  i,
                                                                  i + 2,
                                                                ),
                                                            onRemove: () =>
                                                                controller
                                                                    .removeStop(
                                                                      stops[i],
                                                                    ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 15),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: AnimatedBuilder(
                                          animation: mapSheetChanges,
                                          builder: (context, _) => ItineraryMap(
                                            key: const ValueKey(
                                              'itinerary-map',
                                            ),
                                            origin: trip.origin,
                                            destination: trip.arrivalPlace,
                                            bottomInset:
                                                ((sheet.isAttached
                                                            ? sheet.size
                                                            : middleSheet) *
                                                        mapBounds.maxHeight)
                                                    .clamp(0.0, mapHeight),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  NotificationListener<
                                    DraggableScrollableNotification
                                  >(
                                    onNotification: (n) {
                                      _queueSheetUpdate();
                                      return false;
                                    },
                                    child: DraggableScrollableSheet(
                                      key: const ValueKey(
                                        'itinerary-transport-sheet',
                                      ),
                                      controller: sheet,
                                      initialChildSize: middleSheet,
                                      minChildSize: minimumSheet,
                                      maxChildSize: 1,
                                      snap: true,
                                      snapSizes: [minimumSheet, middleSheet, 1],
                                      snapAnimationDuration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      expand: true,
                                      builder: (context, scroll) =>
                                          ItineraryTransportSheet(
                                            collapsed: collapsed,
                                            aiProposal:
                                                AiTransportProposalPanel(
                                                  fromId: from?.id,
                                                  toId: to?.id,
                                                ),
                                            onHeaderDragStart: _startHeaderDrag,
                                            onHeaderDragUpdate:
                                                _updateHeaderDrag,
                                            onHeaderDragEnd: _endHeaderDrag,
                                            onHeaderDragCancel:
                                                _cancelHeaderDrag,
                                            scrollController: scroll,
                                            from: from,
                                            to: to,
                                            date: trip.travelDate,
                                            selected: selected,
                                            data: data,
                                            journeys: journeys,
                                            walkingOnly: walkingOnly,
                                            earliestDepartureSeconds:
                                                earliestDepartureSeconds,
                                            index: originSelected
                                                ? 0
                                                : returnSelected
                                                ? stops.length
                                                : index + 1,
                                            segmentCount: stops.isEmpty
                                                ? 0
                                                : stops.length + 1,
                                            onPrevious:
                                                !originSelected &&
                                                    stops.isNotEmpty
                                                ? () => setState(
                                                    () =>
                                                        segment = returnSelected
                                                        ? stops.length > 1
                                                              ? stops.length - 2
                                                              : -1
                                                        : index - 1,
                                                  )
                                                : null,
                                            onNext:
                                                !returnSelected &&
                                                    stops.isNotEmpty
                                                ? () => setState(
                                                    () =>
                                                        segment = originSelected
                                                        ? stops.length > 1
                                                              ? 0
                                                              : -2
                                                        : index <
                                                              stops.length - 2
                                                        ? index + 1
                                                        : -2,
                                                  )
                                                : null,
                                            onRefresh: () {
                                              ref.invalidate(
                                                itineraryJourneysProvider(
                                                  journeyKey,
                                                ),
                                              );
                                              if (endpointSelected) {
                                                ref.invalidate(
                                                  returnSelected
                                                      ? arrivalProvider
                                                      : originProvider,
                                                );
                                              }
                                              ref.invalidate(
                                                transportDataProvider(key),
                                              );
                                            },
                                            onSelect: (c) {
                                              if (from != null && to != null) {
                                                _select(c, from, to);
                                              }
                                            },
                                            onClear: selected == null
                                                ? null
                                                : () =>
                                                      controller.clearTransport(
                                                        from!.id,
                                                        to!.id,
                                                      ),
                                            onMap: () => _sheetTo(minimumSheet),
                                            onExpand: () => _sheetTo(1),
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
            ),
          ),
          if (isEmpty)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.white.withValues(alpha: .8),
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.route_outlined,
                            size: 56,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'まだ体験が保存されていません',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xff151515),
                              shadows: [
                                Shadow(color: Colors.white, blurRadius: 8),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '体験を保存すると、旅程の作成ができます。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: color.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                              height: 1.7,
                            ),
                          ),
                          const SizedBox(height: 28),
                          FindExperiencesButton(onPressed: _searchExperiences),
                        ],
                      ),
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
