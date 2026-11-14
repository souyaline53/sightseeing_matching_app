import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/catalog_data.dart';
import '../../data/departure_places.dart';
import '../../model/search_settings.dart';
import '../../state/itinerary_navigation.dart';
import '../../state/itinerary_setup_state.dart';
import '../../state/trip_library_state.dart';
import '../../state/trip_state.dart';
import '../../widgets/travel_photo.dart';
import 'ai_trip_panel.dart';

class ItinerarySetupScreen extends ConsumerStatefulWidget {
  const ItinerarySetupScreen({super.key});
  @override
  ConsumerState<ItinerarySetupScreen> createState() =>
      _ItinerarySetupScreenState();
}

class _ItinerarySetupScreenState extends ConsumerState<ItinerarySetupScreen> {
  String? error;

  Future<void> choosePlace({required bool origin}) async {
    final setup = ref.read(itinerarySetupProvider);
    final current = origin ? setup.conditions.origin : setup.destination;
    final places = ref.read(departurePlacesProvider).value ?? [];
    final names = {'札幌駅', current, ...places.map((p) => p.name)};
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(origin ? '出発地' : '到着地'),
        children: [
          for (final name in names.where((name) => name.trim().isNotEmpty))
            SimpleDialogOption(
              onPressed: isDepartureSelectable(name)
                  ? () => Navigator.pop(context, name)
                  : null,
              child: Text(
                isDepartureSelectable(name) ? placeLabel(name) : '$name（未対応）',
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final latest = ref.read(itinerarySetupProvider);
    ref
        .read(itinerarySetupProvider.notifier)
        .update(
          origin
              ? latest.copyWith(
                  conditions: latest.conditions.copyWith(origin: picked),
                )
              : latest.copyWith(destination: picked),
        );
  }

  String placeLabel(String name) => name == '札幌駅' ? 'JR札幌駅' : name;

  Future<void> chooseLength() async {
    final length = await showDialog<TripLength>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('泊数'),
        children: [
          for (final value in [
            TripLength.day,
            TripLength.halfDay,
            TripLength.overnight,
            TripLength.longer,
          ])
            SimpleDialogOption(
              onPressed: value == TripLength.day || value == TripLength.halfDay
                  ? () => Navigator.pop(context, value)
                  : null,
              child: Text(
                value == TripLength.day || value == TripLength.halfDay
                    ? value.label
                    : '${value.label}（対応予定）',
                style: TextStyle(
                  color:
                      value == TripLength.overnight ||
                          value == TripLength.longer
                      ? Theme.of(context).disabledColor
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
    if (length == null || !mounted) return;
    final latest = ref.read(itinerarySetupProvider);
    ref
        .read(itinerarySetupProvider.notifier)
        .update(
          latest.copyWith(
            conditions: latest.conditions.copyWith(length: length),
          ),
        );
  }

  Future<void> chooseMode() async {
    final mode = await showDialog<TravelMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('交通手段'),
        children: [
          for (final value in TravelMode.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Text(value.label),
            ),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    final latest = ref.read(itinerarySetupProvider);
    ref
        .read(itinerarySetupProvider.notifier)
        .update(
          latest.copyWith(
            conditions: latest.conditions.copyWith(transport: mode),
          ),
        );
  }

  Future<void> chooseDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final current = ref.read(itinerarySetupProvider).conditions.resolveDate();
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(today) ? today : current,
      firstDate: today,
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (picked == null || !mounted) return;
    final latest = ref.read(itinerarySetupProvider);
    ref
        .read(itinerarySetupProvider.notifier)
        .update(
          latest.copyWith(
            conditions: latest.conditions.copyWith(
              dateChoice: DateChoice.fixed,
              fixedDate: picked,
            ),
          ),
        );
    setState(() => error = null);
  }

  Future<void> chooseTime() async {
    final minutes = ref.read(itinerarySetupProvider).departureMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null || !mounted) return;
    ref
        .read(itinerarySetupProvider.notifier)
        .update(
          ref
              .read(itinerarySetupProvider)
              .copyWith(departureMinutes: picked.hour * 60 + picked.minute),
        );
  }

  void create({required bool ai}) {
    final setup = ref.read(itinerarySetupProvider);
    final saved = ref.read(savedExperiencesProvider);
    final current = {
      for (final e in ref.read(catalogProvider).requireValue.experiences)
        e.id: e,
    };
    final stops = saved
        .where((e) => setup.selectedIds.contains(e.id))
        .map((e) => current[e.id] ?? e)
        .toList();
    if (stops.isEmpty) return;
    if (setup.conditions.length != TripLength.halfDay &&
        setup.conditions.length != TripLength.day) {
      setState(() => error = '半日または日帰りを選択してください。');
      return;
    }
    final validation = setup.conditions.validate();
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    ref
        .read(tripProvider.notifier)
        .createItinerary(
          conditions: setup.conditions,
          destination: setup.destination,
          departureMinutes: setup.departureMinutes,
          stops: stops,
        );
    if (ai) ref.read(aiSetupIntentProvider.notifier).open();
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(itinerarySetupProvider);
    final conditions = setup.conditions;
    final saved = ref.watch(savedExperiencesProvider);
    final catalog = ref.watch(catalogProvider).value;
    final selected = saved
        .where((e) => setup.selectedIds.contains(e.id))
        .length;
    final date = conditions.resolveDate();
    final today = DateUtils.dateOnly(DateTime.now());
    Widget field(
      IconData icon,
      String label,
      String value,
      VoidCallback onTap, {
      Key? key,
    }) => ListTile(
      key: key,
      leading: Icon(icon),
      title: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('旅程作成'),
        actions: [
          if (ref.watch(tripProvider).stops.isNotEmpty)
            IconButton(
              tooltip: '作成済みの旅程を編集',
              onPressed: () =>
                  ref.read(itineraryEditorProvider.notifier).open(),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                field(
                  Icons.trip_origin,
                  '出発地',
                  placeLabel(conditions.origin),
                  () => choosePlace(origin: true),
                  key: const ValueKey('setup-origin'),
                ),
                field(
                  Icons.flag_outlined,
                  '到着地',
                  placeLabel(setup.destination),
                  () => choosePlace(origin: false),
                  key: const ValueKey('setup-destination'),
                ),
                field(
                  Icons.calendar_today_outlined,
                  '日付',
                  date == today
                      ? '今日の日付'
                      : '${date.year}/${date.month}/${date.day}',
                  chooseDate,
                  key: const ValueKey('setup-date'),
                ),
                field(
                  Icons.schedule,
                  '出発時刻',
                  '${setup.departureMinutes ~/ 60}:${(setup.departureMinutes % 60).toString().padLeft(2, '0')}',
                  chooseTime,
                  key: const ValueKey('setup-time'),
                ),
                field(
                  Icons.bed_outlined,
                  '泊数',
                  conditions.length.label,
                  chooseLength,
                  key: const ValueKey('setup-length'),
                ),
                field(
                  Icons.directions_transit,
                  '交通手段',
                  conditions.transport.label,
                  chooseMode,
                  key: const ValueKey('setup-transport'),
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            '保存した観光地から選ぶ',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (saved.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('保存した観光地はまだありません', textAlign: TextAlign.center),
            ),
          for (final savedSpot in saved)
            Builder(
              builder: (context) {
                final spot =
                    catalog?.experiences
                        .where((e) => e.id == savedSpot.id)
                        .firstOrNull ??
                    savedSpot;
                return CheckboxListTile(
                  key: ValueKey('setup-spot-${spot.id}'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  secondary: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 56,
                      height: 52,
                      child: TravelPhoto(spot),
                    ),
                  ),
                  title: Text(
                    spot.displayName,
                    style: const TextStyle(fontSize: 14),
                  ),
                  value: setup.selectedIds.contains(spot.id),
                  onChanged: (_) =>
                      ref.read(itinerarySetupProvider.notifier).toggle(spot.id),
                );
              },
            ),
        ],
      ),
      bottomNavigationBar: selected == 0
          ? null
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('setup-create-manual'),
                      onPressed: () => create(ai: false),
                      child: const Text('旅程を作成'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('setup-create-ai'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 50),
                      ),
                      onPressed: () => create(ai: true),
                      child: const Text(
                        'AIで旅を組み立てる\n(beta版)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
