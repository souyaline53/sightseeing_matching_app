import '../../theme/app_theme.dart';
import '../../service/transport/transport_itinerary_service.dart';
import '../../model/ai_trip_draft.dart';
import '../../model/ai_trip_segment.dart';
import '../../data/catalog_data.dart';
import 'ai_transport_card.dart';
import 'plan_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/departure_places.dart';
import '../../model/transport.dart';
import '../../service/transport/ai_trip_repository.dart';
import '../../state/trip_state.dart';
import '../../state/trip_library_state.dart';

final aiSetupIntentProvider = NotifierProvider<AiSetupIntent, int>(
  AiSetupIntent.new,
);

class AiSetupIntent extends Notifier<int> {
  @override
  int build() => 0;
  void open() => state++;
  void clear() => state = 0;
}

final aiRestoreIntentProvider = NotifierProvider<AiSetupIntent, int>(
  AiSetupIntent.new,
);
final aiRefreshIntentProvider = NotifierProvider<AiSetupIntent, int>(
  AiSetupIntent.new,
);

final aiTripDocumentProvider = StreamProvider.family<Json, String>(
  (ref, id) => ref.watch(aiTripRepositoryProvider).watch(id),
);

class AiTripPanel extends ConsumerStatefulWidget {
  const AiTripPanel({super.key});
  @override
  ConsumerState<AiTripPanel> createState() => _AiTripPanelState();
}

class _AiTripPanelState extends ConsumerState<AiTripPanel> {
  bool busy = false;
  int seenIntent = 0, seenRestore = 0, seenRefresh = 0;
  Timer? quotaTimer;
  @override
  void dispose() {
    quotaTimer?.cancel();
    super.dispose();
  }

  String? error;
  void notice(String value) {
    if (!mounted) return;
    setState(() => error = value);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(value),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '閉じる',
          onPressed: () => messenger.hideCurrentSnackBar(),
        ),
      ),
    );
  }

  Future<void> restore() async {
    try {
      final records = await ref.read(aiTripRepositoryProvider).saved();
      if (!mounted) return;
      final record = await showDialog<Json>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('保存済みのAIの旅'),
          children: [
            if (records.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('保存された旅はありません。'),
              ),
            for (final r in records)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, r),
                child: Text(
                  (r['currentTrip'] as Map)['title'] as String? ?? '保存した旅',
                ),
              ),
          ],
        ),
      );
      if (record == null || !mounted) return;
      final saved = TripState.fromJson(
        Map<String, dynamic>.from(record['currentTrip'] as Map),
      );
      final trip = saved.copyWith(
        ai: {
          ...saved.ai,
          'rootId': record['rootId'],
          'status': record['aiGenerationStatus'],
          'requestId': record['aiGenerationRequestId'],
        },
      );
      ref.read(tripLibraryProvider.notifier).upsert(trip);
      if (record['aiResult'] is Map && trip.ai['result'] == null) {
        ref
            .read(tripProvider.notifier)
            .acceptAi(
              Map<String, dynamic>.from(record['aiResult'] as Map),
              trip.ai['generationBasis'] as String? ?? '',
            );
      }
    } catch (_) {
      notice('保存済みの旅を取得できませんでした。ログインと通信状態を確認してください。');
    }
  }

  Future<void> generate() async {
    if (busy ||
        ref.read(tripProvider).aiLocked ||
        ref.read(tripProvider).aiQuotaBlocked) {
      return;
    }
    final before = ref.read(tripProvider);
    if (before.stops.isEmpty || before.stops.length > 3) {
      notice('AIで作成する観光地は1〜3件にしてください。');
      return;
    }
    final input = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiTripConditionsSheet(trip: before),
    );
    if (input == null || !mounted) return;
    if (ref.read(tripProvider).id != before.id ||
        ref.read(tripProvider).aiBasis != before.aiBasis) {
      notice('旅程が変更されました。条件を確認してください。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final repo = ref.read(aiTripRepositoryProvider);
    String? root;
    try {
      final registration = await repo.register(before);
      root = registration['tripId'] as String;
      if (!mounted || ref.read(tripProvider).id != before.id) return;
      final status = registration['aiGenerationStatus'] as String;
      ref.read(tripProvider.notifier).replaceAi({
        ...ref.read(tripProvider).ai,
        'rootId': root,
        'status': status,
      });
      if (ref.read(tripProvider).aiBasis != before.aiBasis) {
        notice('旅程が変更されました。条件を確認してから作成してください。');
        return;
      }
      if (['processing', 'uncertain'].contains(status)) {
        await refresh(root);
        return;
      }
      final notifier = ref.read(tripProvider.notifier);
      final configured = ref
          .read(tripProvider)
          .copyWith(ai: {...ref.read(tripProvider).ai, 'config': input});
      final basis = configured.aiBasis;
      final requestId = 'request-${DateTime.now().microsecondsSinceEpoch}';
      notifier.replaceAi({
        ...configured.ai,
        'status': 'processing',
        'requestId': requestId,
        'generationBasis': basis,
      });
      await ref.read(tripLibraryProvider.notifier).flush();
      final generated = await ref
          .read(transportItineraryServiceProvider)
          .optimizeTrip(tripId: root, requestId: requestId, input: input);
      final response = <String, dynamic>{
        'success': true,
        'itinerary': generated.itinerary.toJson(),
        'message': generated.message,
        'aiMetadata': generated.metadata,
      };
      if (!mounted || ref.read(tripProvider).id != before.id) return;
      notifier.acceptAi(response, basis);
      await ref.read(tripLibraryProvider.notifier).flush();
      final applied = ref.read(tripProvider);
      if (mounted && applied.aiProposalValid) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlanScreen(
              tripId: applied.id,
              stops: applied.stops,
              origin: applied.origin,
              date: applied.travelDate,
              publicTransport: applied.publicTransport,
              demo: false,
              conditions: applied.conditions,
            ),
          ),
        );
      }
    } catch (failure) {
      if (mounted && ref.read(tripProvider).id == before.id) {
        if (root != null) {
          ref.read(tripProvider.notifier).replaceAi({
            ...ref.read(tripProvider).ai,
            'status': 'uncertain',
          });
          try {
            await refresh(root);
          } catch (_) {
            /* Keep unknown operation locked. */
          }
        }
        if (failure is TransportItineraryException) {
          final details = failure.details;
          final reset = details['reason'] == 'ai-daily-limit'
              ? DateTime.tryParse(details['resetAt'] as String? ?? '')
              : details['reason'] == 'ai-minute-limit'
              ? DateTime.now().add(
                  Duration(
                    seconds:
                        (details['retryAfterSeconds'] as num?)?.toInt() ?? 60,
                  ),
                )
              : null;
          if (reset != null) {
            ref.read(tripProvider.notifier).replaceAi({
              ...ref.read(tripProvider).ai,
              'blockedUntil': reset.millisecondsSinceEpoch,
            });
          }
        }
        notice(
          failure is TransportItineraryException
              ? failure.message
              : 'AIの作成を完了できませんでした。ログイン・入力条件と保存状態を確認してください。結果確認待ちの場合は再実行しません。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh(String root) async {
    final repository = ref.read(aiTripRepositoryProvider);
    var data = await repository.read(root);
    if (mounted &&
        ref.read(tripProvider).ai['rootId'] == root &&
        data?['aiGenerationStatus'] == 'processing' &&
        data?['aiGenerationPhase'] == 'reserved' &&
        DateTime.now().millisecondsSinceEpoch -
                (data?['aiGenerationStartedAt'] as num).toInt() >=
            600000) {
      await repository.register(ref.read(tripProvider));
      data = await repository.read(root);
    }
    if (!mounted ||
        data == null ||
        ref.read(tripProvider).ai['rootId'] != root) {
      return;
    }
    final trip = ref.read(tripProvider);
    // A failed new attempt must not adopt the previous generation's result.
    if (trip.ai['requestId'] != null &&
        trip.ai['requestId'] != data['aiGenerationRequestId'] &&
        trip.aiStatus != 'completed') {
      final status =
          ['processing', 'uncertain'].contains(data['aiGenerationStatus'])
          ? data['aiGenerationStatus']
          : 'failed';
      if (trip.aiStatus == status) return;
      ref.read(tripProvider.notifier).replaceAi({...trip.ai, 'status': status});
      return;
    }
    if (data['aiResult'] is Map &&
        data['aiGenerationStatus'] == 'completed' &&
        (trip.ai['result'] == null ||
            trip.ai['resultRequestId'] != data['aiGenerationRequestId'])) {
      ref
          .read(tripProvider.notifier)
          .acceptAi(
            Map<String, dynamic>.from(data['aiResult'] as Map),
            trip.ai['generationBasis'] as String? ?? '',
          );
    } else {
      ref.read(tripProvider.notifier).replaceAi({
        ...trip.ai,
        'status': data['aiGenerationStatus'],
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripProvider);
    final intent = ref.watch(aiSetupIntentProvider);
    if (intent != 0 && intent != seenIntent) {
      seenIntent = intent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(aiSetupIntentProvider) != 0) {
          ref.read(aiSetupIntentProvider.notifier).clear();
          seenIntent = 0;
          generate();
        }
      });
    }
    final restoreIntent = ref.watch(aiRestoreIntentProvider),
        refreshIntent = ref.watch(aiRefreshIntentProvider);
    if (restoreIntent != seenRestore) {
      seenRestore = restoreIntent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) restore();
      });
    }
    if (refreshIntent != seenRefresh) {
      seenRefresh = refreshIntent;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final root = ref.read(tripProvider).ai['rootId'];
        if (mounted && root is String) {
          try {
            await refresh(root);
          } catch (_) {
            notice('保存状態を確認できませんでした。');
          }
        }
      });
    }
    quotaTimer?.cancel();
    if (trip.aiQuotaBlocked) {
      final id = trip.id;
      quotaTimer = Timer(
        Duration(
          milliseconds:
              (trip.ai['blockedUntil'] as int) -
              DateTime.now().millisecondsSinceEpoch +
              50,
        ),
        () {
          if (mounted && ref.read(tripProvider).id == id) {
            final ai = {...ref.read(tripProvider).ai}..remove('blockedUntil');
            ref.read(tripProvider.notifier).replaceAi(ai);
          }
        },
      );
    }
    final root = trip.ai['rootId'];
    if (root is String) {
      ref.listen(aiTripDocumentProvider(root), (_, next) {
        final data = next.value;
        if (!busy &&
            data != null &&
            data['aiGenerationStatus'] != ref.read(tripProvider).aiStatus) {
          unawaited(refresh(root).catchError((_) {}));
        }
      });
    }
    return OutlinedButton.icon(
      key: const ValueKey('ai-create-trip'),
      onPressed: busy || trip.aiLocked || trip.aiQuotaBlocked ? null : generate,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome, size: 15),
      label: const Text('AIで旅程を組み立てる(ベータ版)', style: TextStyle(fontSize: 12)),
    );
  }
}

class AiTripConditionsSheet extends ConsumerStatefulWidget {
  final TripState trip;
  const AiTripConditionsSheet({super.key, required this.trip});
  @override
  ConsumerState<AiTripConditionsSheet> createState() =>
      _AiTripConditionsSheetState();
}

class _AiTripConditionsSheetState extends ConsumerState<AiTripConditionsSheet> {
  final form = GlobalKey<FormState>();
  final stays = <String, TextEditingController>{};
  late DateTime departureDate, arrivalDate;
  late TimeOfDay departureTime, arrivalTime;
  late String origin, destination;
  String? originStop, destinationStop, error;
  @override
  void initState() {
    super.initState();
    final trip = widget.trip;
    final config = trip.ai['config'] as Map? ?? {};
    departureDate = trip.travelDate ?? trip.conditions.resolveDate();
    arrivalDate = tripArrivalDate(departureDate, trip.conditions.length);
    departureTime = TimeOfDay(
      hour: trip.departureMinutes ~/ 60,
      minute: trip.departureMinutes % 60,
    );
    arrivalTime = const TimeOfDay(hour: 18, minute: 0);
    origin = trip.origin;
    destination = trip.arrivalPlace;
    for (final e in trip.stops) {
      stays[e.id] = TextEditingController(
        text: '${trip.stayMinutes[e.id] ?? e.minutes}',
      );
    }
    if (config['destination'] is Map) {
      destination =
          (config['destination'] as Map)['id'] as String? ?? destination;
    }
  }

  @override
  void dispose() {
    for (final c in stays.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get dayOffset =>
      DateTime.utc(arrivalDate.year, arrivalDate.month, arrivalDate.day)
          .difference(
            DateTime.utc(
              departureDate.year,
              departureDate.month,
              departureDate.day,
            ),
          )
          .inDays;
  String dateLabel(DateTime d) =>
      '${d.month}月${d.day}日（${['月', '火', '水', '木', '金', '土', '日'][d.weekday - 1]}）';
  String clock(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  Future<void> pickDate(bool first) async {
    final d = await showDatePicker(
      context: context,
      initialDate: first ? departureDate : arrivalDate,
      firstDate: first ? DateTime(2020) : departureDate,
      lastDate: first
          ? DateTime(DateTime.now().year + 3)
          : DateTime(
              departureDate.year,
              departureDate.month,
              departureDate.day + 2,
            ),
    );
    if (d != null) {
      setState(() {
        if (first) {
          departureDate = d;
          arrivalDate = tripArrivalDate(d, widget.trip.conditions.length);
        } else {
          arrivalDate = d;
        }
      });
    }
  }

  Future<void> pickTime(bool first) async {
    final t = await showTimePicker(
      context: context,
      initialTime: first ? departureTime : arrivalTime,
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (t != null) {
      setState(() {
        if (first) {
          departureTime = t;
        } else {
          arrivalTime = t;
        }
      });
    }
  }

  Widget section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 3, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: child,
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final places =
        ref
            .watch(departurePlacesProvider)
            .value
            ?.where((p) => isDepartureSelectable(p.name))
            .toList() ??
        <DeparturePlace>[];
    DeparturePlace? find(String id) =>
        places.where((p) => p.id == id).firstOrNull;
    final a = find(origin), b = find(destination);
    originStop = a?.accessStops.any((s) => s.stopId == originStop) == true
        ? originStop
        : a == null
        ? null
        : defaultBoardingStop(a.name, a.accessStops)?.stopId;
    destinationStop =
        b?.accessStops.any((s) => s.stopId == destinationStop) == true
        ? destinationStop
        : b == null
        ? null
        : defaultBoardingStop(b.name, b.accessStops)?.stopId;
    Widget endpoint(bool first) {
      final id = first ? origin : destination, p = first ? a : b;
      return Column(
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(first ? 'ai-origin-place' : 'ai-destination-place'),
            initialValue: find(id) == null ? null : id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: first ? '出発地' : '到着地',
              border: InputBorder.none,
              prefixIcon: Icon(
                first ? Icons.trip_origin : Icons.location_on_outlined,
                size: 20,
              ),
            ),
            items: places
                .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                .toList(),
            validator: (v) => v == null ? '地点を選択してください' : null,
            onChanged: (v) => setState(() {
              if (v == null) return;
              if (first) {
                origin = v;
                originStop = null;
              } else {
                destination = v;
                destinationStop = null;
              }
            }),
          ),
          const Divider(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(
              '${first ? 'ai-origin-stop' : 'ai-destination-stop'}-$id',
            ),
            initialValue: first ? originStop : destinationStop,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: first ? '出発駅・バス停' : '到着駅・バス停',
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.train_outlined, size: 20),
            ),
            items: [
              for (final s in p?.accessStops ?? <AccessStop>[])
                if (s.data['isActive'] != false && s.status != 'sample')
                  DropdownMenuItem(
                    value: s.stopId,
                    child: Text(
                      boardingStopLabel(s),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
            ],
            validator: (v) => v == null ? '駅・バス停を選択してください' : null,
            onChanged: (v) => setState(() {
              if (first) {
                originStop = v;
              } else {
                destinationStop = v;
              }
            }),
          ),
        ],
      );
    }

    Widget dateTime(bool first) => Row(
      children: [
        Expanded(
          flex: 3,
          child: TextButton.icon(
            key: ValueKey(first ? 'ai-departure-date' : 'ai-arrival-date'),
            onPressed: () => pickDate(first),
            icon: const Icon(Icons.calendar_today_outlined, size: 17),
            label: Text(
              dateLabel(first ? departureDate : arrivalDate),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        Container(width: 1, height: 24, color: AppColors.border),
        Expanded(
          flex: 2,
          child: TextButton.icon(
            key: ValueKey(first ? 'ai-departure-time' : 'ai-arrival-time'),
            onPressed: () => pickTime(first),
            icon: const Icon(Icons.schedule, size: 17),
            label: Text(
              clock(first ? departureTime : arrivalTime),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
    return Container(
      height: MediaQuery.sizeOf(context).height * .91,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 12, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: Theme.of(context).colorScheme.primary,
                    size: 21,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'AIで旅を組み立てる',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: '閉じる',
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: form,
                child: SingleChildScrollView(
                  key: const ValueKey('ai-conditions-scroll'),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      section('出発', endpoint(true)),
                      section('到着', endpoint(false)),
                      section('出発日時', dateTime(true)),
                      section('到着日時', dateTime(false)),
                      const Padding(
                        padding: EdgeInsets.only(left: 3, bottom: 8),
                        child: Text(
                          '観光地での滞在時間',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      for (var i = 0; i < widget.trip.stops.length; i++)
                        section(
                          '${i + 1}',
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.trip.stops[i].displayName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 88,
                                child: TextFormField(
                                  key: ValueKey(
                                    'ai-stay-${widget.trip.stops[i].id}',
                                  ),
                                  controller: stays[widget.trip.stops[i].id],
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    suffixText: '分',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(12),
                                      ),
                                    ),
                                  ),
                                  validator: (v) {
                                    final n = int.tryParse(v ?? '');
                                    return n != null && n > 0 && n <= 1440
                                        ? null
                                        : '1〜1440';
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (error != null)
                        Text(
                          error!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () {
                    if (!form.currentState!.validate() ||
                        a == null ||
                        b == null) {
                      return;
                    }
                    final depart =
                            (departureTime.hour * 60 + departureTime.minute) *
                            60,
                        deadline =
                            dayOffset * 86400 +
                            (arrivalTime.hour * 60 + arrivalTime.minute) * 60;
                    if (dayOffset < 0 || dayOffset > 2 || deadline <= depart) {
                      setState(() => error = '到着日時は出発より後に設定してください。');
                      return;
                    }
                    final from = a.accessStops
                            .where((s) => s.stopId == originStop)
                            .firstOrNull,
                        to = b.accessStops
                            .where((s) => s.stopId == destinationStop)
                            .firstOrNull;
                    if (from == null || to == null) return;
                    Json place(DeparturePlace p, AccessStop s) => {
                      'id': p.id,
                      'name': p.name,
                      'latitude': p.point.latitude,
                      'longitude': p.point.longitude,
                      'accessStops': [boardingAccess(s)],
                    };
                    final catalog = ref.read(catalogProvider).value;
                    try {
                      final visits = <Json>[];
                      for (final saved in widget.trip.stops) {
                        final spot =
                            catalog?.experiences
                                .where((e) => e.id == saved.id)
                                .firstOrNull ??
                            saved;
                        final access = spot.accessStops
                            .where(
                              (s) =>
                                  s.data['isActive'] != false &&
                                  s.status != 'sample' &&
                                  s.walkingMinutes != null,
                            )
                            .map(
                              (s) => <String, dynamic>{
                                ...s.toJson(),
                                'useRegisteredWalking': true,
                              },
                            )
                            .toList();
                        if (access.isEmpty) {
                          throw StateError(
                            '${spot.displayName}の駅・バス停との接続情報が未登録です。手動で旅程を作成してください。',
                          );
                        }
                        visits.add({
                          'id': spot.id,
                          'name': spot.displayName,
                          if (spot.latitude != null &&
                              spot.longitude != null) ...{
                            'latitude': spot.latitude,
                            'longitude': spot.longitude,
                          },
                          'accessStops': access,
                          'staySeconds': int.parse(stays[spot.id]!.text) * 60,
                          'opening': tripOpening(
                            spot,
                            departureDate,
                            arrivalDate,
                          ),
                        });
                      }
                      Navigator.pop(context, <String, dynamic>{
                        'date':
                            '${departureDate.year}-${departureDate.month.toString().padLeft(2, '0')}-${departureDate.day.toString().padLeft(2, '0')}',
                        'origin': place(a, from),
                        'destination': place(b, to),
                        'departureSeconds': depart,
                        'deadlineSeconds': deadline,
                        'modes': ['rail', 'bus', 'walk'],
                        'preference': 'transfers',
                        'minimumTransferSeconds': 300,
                        'visits': visits,
                      });
                    } catch (e) {
                      setState(
                        () => error = e is StateError
                            ? e.message
                            : '観光地情報を読み取れませんでした。登録内容を確認してください。',
                      );
                    }
                  },
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text(
                    'AIで旅程を作成',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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

class AiTransportProposalPanel extends ConsumerWidget {
  final String? fromId, toId;
  const AiTransportProposalPanel({super.key, this.fromId, this.toId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider);
    final segments = aiTripSegments(trip)
        .where(
          (s) =>
              (fromId == null || s.fromId == fromId) &&
              (toId == null || s.toId == toId) &&
              s.steps.isNotEmpty,
        )
        .toList();
    return Column(
      children: [
        for (final s in segments)
          AiTransportCard(
            segment: s,
            needsReview: !trip.aiProposalValid || trip.ai['enabled'] == false,
          ),
      ],
    );
  }
}
