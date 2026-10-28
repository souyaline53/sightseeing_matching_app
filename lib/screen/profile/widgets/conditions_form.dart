import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../model/search_settings.dart';

/// Shared editor for profile defaults and saved presets, not the search wizard.
class ConditionsForm extends HookConsumerWidget {
  final SearchConditions value;
  final ValueChanged<SearchConditions> onChanged;
  final bool profileOnly;
  const ConditionsForm({
    super.key,
    required this.value,
    required this.onChanged,
    this.profileOnly = false,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = useRef(value);
    latest.value = value;
    void emit(SearchConditions next) {
      latest.value = next;
      onChanged(next);
    }

    final origin = useTextEditingController(text: value.origin);
    useEffect(() {
      if (origin.text != value.origin) origin.text = value.origin;
      return null;
    }, [value.origin]);
    Widget choices<T>(
      String label,
      List<T> options,
      T selected,
      String Function(T) title,
      ValueChanged<T> change,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(title(option)),
                  selected: selected == option,
                  onSelected: (_) => change(option),
                ),
            ],
          ),
        ],
      ),
    );
    Widget walking() => choices(
      '徒歩負担',
      Walking.values,
      value.walking,
      (e) => e.label,
      (e) => emit(latest.value.copyWith(walking: e)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: origin,
          decoration: const InputDecoration(
            labelText: '出発地（駅名・地域名）',
            prefixIcon: Icon(Icons.trip_origin),
          ),
          onChanged: (v) => emit(latest.value.copyWith(origin: v)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final name in ['札幌駅', '小樽駅', '新千歳空港'])
              ActionChip(
                label: Text(name),
                onPressed: () => emit(latest.value.copyWith(origin: name)),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (!profileOnly) ...[
          choices(
            '旅行日',
            DateChoice.values,
            value.dateChoice,
            (e) => ['明日', '週末', '日付指定'][e.index],
            (e) => emit(latest.value.copyWith(dateChoice: e)),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final today = DateUtils.dateOnly(DateTime.now());
              final resolved = value.resolveDate();
              final picked = await showDatePicker(
                context: context,
                initialDate: resolved.isBefore(today) ? today : resolved,
                firstDate: today,
                lastDate: DateTime(today.year + 10, 12, 31),
              );
              if (picked != null) {
                onChanged(
                  value.copyWith(
                    dateChoice: DateChoice.fixed,
                    fixedDate: picked,
                  ),
                );
              }
            },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(
              '${value.resolveDate().year}年${value.resolveDate().month}月${value.resolveDate().day}日',
            ),
          ),
          if (value.dateChoice == DateChoice.fixed &&
              value.validate()?.contains('日付') == true)
            const Text(
              '過去の日付です。旅行日を選び直してください。',
              style: TextStyle(color: Colors.red),
            ),
          const SizedBox(height: 20),
        ],
        choices(
          '移動手段',
          TravelMode.values,
          value.transport,
          (e) => e.label,
          (e) => emit(latest.value.copyWith(transport: e)),
        ),
        if (!profileOnly)
          choices(
            '旅行期間',
            TripLength.values,
            value.length,
            (e) => e.label,
            (e) => emit(latest.value.copyWith(length: e)),
          ),
        Text(
          '${profileOnly ? '通常の旅行予算' : '総予算上限'}：${value.budget}円',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text('交通費・食事・体験・宿泊などを含む旅行全体の上限', style: TextStyle(fontSize: 12)),
        Slider(
          value: value.budget.toDouble(),
          min: 1000,
          max: 100000,
          divisions: 99,
          label: '${value.budget}円',
          onChanged: (v) => emit(latest.value.copyWith(budget: v.round())),
        ),
        if (profileOnly)
          walking()
        else
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('さらに細かく設定'),
            subtitle: Text(
              '片道${value.maxMinutes}分以内 · 徒歩${value.walking.label} · ${value.company.label}',
            ),
            children: [
              Text('片道移動時間の上限：${value.maxMinutes}分'),
              Slider(
                value: value.maxMinutes.toDouble(),
                min: 30,
                max: 300,
                divisions: 18,
                label: '${value.maxMinutes}分',
                onChanged: (v) =>
                    emit(latest.value.copyWith(maxMinutes: v.round())),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  '公共交通では距離より移動時間を重視します。現段階では経路を検索せず、条件の保存・引継ぎのみ行います。',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              walking(),
              choices(
                '同行者',
                Company.values,
                value.company,
                (e) => e.label,
                (e) => emit(latest.value.copyWith(company: e)),
              ),
            ],
          ),
      ],
    );
  }
}
