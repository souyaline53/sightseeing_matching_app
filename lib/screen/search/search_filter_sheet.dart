import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../data/departure_places.dart';
import '../../model/search_settings.dart';
import '../../state/discovery_state.dart';
import '../../state/settings_state.dart';
import '../../state/trip_state.dart';

Future<void> showSearchFilterSheet(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: const _SearchFilterSheet(),
    ),
  );
}

class _SearchFilterSheet extends HookConsumerWidget {
  const _SearchFilterSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = useState(ref.read(searchDraftProvider));
    final busy = useState(false);
    final error = useState<String?>(null);
    final today = DateUtils.dateOnly(DateTime.now());
    final places = ref.watch(departurePlacesProvider);
    void update(SearchConditions value) => draft.value = value;
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
    Widget choices<T>(
      List<T> values,
      T selected,
      String Function(T) label,
      ValueChanged<T> select,
    ) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(label(value)),
            selected: value == selected,
            onSelected: (_) => select(value),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            showCheckmark: false,
          ),
      ],
    );
    Future<void> apply() async {
      final filters = draft.value;
      error.value = filters.validate() ?? filters.validateFilters();
      if (!isDepartureSelectable(filters.origin) ||
          departureNamed(filters.origin, places.value ?? []) == null) {
        error.value = '対応している出発地を選択してください。';
      }
      if (error.value != null) return;
      busy.value = true;
      try {
        await ref.read(settingsProvider.notifier).saveSearch(filters);
        ref.read(searchDraftProvider.notifier).replace(filters);
        ref.read(tripProvider.notifier).updateSearchFilters(filters);
        ref.read(discoveryProvider.notifier).showExplore();
        if (context.mounted) Navigator.pop(context);
      } catch (_) {
        if (context.mounted) error.value = '検索条件を保存できませんでした。もう一度お試しください。';
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .9,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SEARCH FILTER',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 2,
                            color: Color(0xff007f69),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '検索条件',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '閉じる',
                    onPressed: busy.value ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: AbsorbPointer(
                absorbing: busy.value,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      section(
                        '出発地',
                        places.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, _) => TextButton(
                            onPressed: () =>
                                ref.invalidate(departurePlacesProvider),
                            child: const Text('出発地を読み込み直す'),
                          ),
                          data: (items) => Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final place in items)
                                ChoiceChip(
                                  label: Text(
                                    isDepartureSelectable(place.name)
                                        ? place.name
                                        : '${place.name}（未対応）',
                                  ),
                                  selected:
                                      isDepartureSelectable(place.name) &&
                                      draft.value.origin == place.name,
                                  onSelected: isDepartureSelectable(place.name)
                                      ? (_) => update(
                                          draft.value.copyWith(
                                            origin: place.name,
                                          ),
                                        )
                                      : null,
                                  showCheckmark: false,
                                ),
                            ],
                          ),
                        ),
                      ),
                      section(
                        '移動手段',
                        choices(
                          TravelMode.values,
                          draft.value.transport,
                          (v) => v.label,
                          (v) => update(draft.value.copyWith(transport: v)),
                        ),
                      ),
                      section(
                        '旅行期間',
                        choices(
                          TripLength.values,
                          draft.value.length,
                          (v) => v.label,
                          (v) => update(draft.value.copyWith(length: v)),
                        ),
                      ),
                      section(
                        '出発日',
                        CalendarDatePicker(
                          key: ValueKey(draft.value.resolveDate()),
                          initialDate: draft.value.resolveDate().isBefore(today)
                              ? today
                              : draft.value.resolveDate(),
                          firstDate: today,
                          lastDate: DateTime(today.year + 5, 12, 31),
                          onDateChanged: (date) => update(
                            draft.value.copyWith(
                              dateChoice: DateChoice.fixed,
                              fixedDate: date,
                            ),
                          ),
                        ),
                      ),
                      section(
                        '同行者',
                        choices(
                          Company.values,
                          draft.value.company,
                          (v) => v.label,
                          (v) => update(draft.value.copyWith(company: v)),
                        ),
                      ),
                      section(
                        '総予算上限：${draft.value.budget}円',
                        Slider(
                          value: draft.value.budget.toDouble(),
                          min: 1000,
                          max: 100000,
                          divisions: 99,
                          onChanged: (v) =>
                              update(draft.value.copyWith(budget: v.round())),
                        ),
                      ),
                      section(
                        '片道移動時間の上限：${draft.value.maxMinutes}分',
                        Slider(
                          value: draft.value.maxMinutes.toDouble(),
                          min: 30,
                          max: 300,
                          divisions: 18,
                          onChanged: (v) => update(
                            draft.value.copyWith(maxMinutes: v.round()),
                          ),
                        ),
                      ),
                      section(
                        '歩く量',
                        choices(
                          Walking.values,
                          draft.value.walking,
                          (v) => v.label,
                          (v) => update(draft.value.copyWith(walking: v)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                children: [
                  if (error.value != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        error.value!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: busy.value
                            ? null
                            : () {
                                draft.value = const SearchConditions();
                                error.value = null;
                              },
                        child: const Text('条件をリセット'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: busy.value ? null : apply,
                          child: Text(busy.value ? '検索中…' : 'この条件で検索'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
