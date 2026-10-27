import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/search_settings.dart';
import '../../state/settings_state.dart';

class _StepLayout extends HookConsumerWidget {
  final String title, subtitle;
  final List<Widget> children;
  const _StepLayout({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        ...children,
      ],
    ),
  );
}

class _SelectionCard extends HookConsumerWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _SelectionCard({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: colors.primary, size: 30),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DepartureStepPage extends HookConsumerWidget {
  const DepartureStepPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(searchDraftProvider);
    final origin = useTextEditingController(text: draft.origin);
    useEffect(() {
      if (origin.text != draft.origin) origin.text = draft.origin;
      return null;
    }, [draft.origin]);
    void update(SearchConditions Function(SearchConditions) change) => ref
        .read(searchDraftProvider.notifier)
        .replace(change(ref.read(searchDraftProvider)));
    return _StepLayout(
      title: 'どこから、どうやって行く？',
      subtitle: '出発地と、無理なく行ける範囲を決めましょう。',
      children: [
        TextField(
          key: const ValueKey('search-origin'),
          controller: origin,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '出発地（駅名・地域名）',
            prefixIcon: Icon(Icons.trip_origin),
          ),
          onChanged: (value) => update((c) => c.copyWith(origin: value)),
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final name in ['札幌駅', '小樽駅', '新千歳空港'])
              ActionChip(
                label: Text(name),
                onPressed: () => update((c) => c.copyWith(origin: name)),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('移動手段', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final mode in TravelMode.values) ...[
              if (mode.index > 0) const SizedBox(width: 8),
              Expanded(
                child: _SelectionCard(
                  key: ValueKey('travel-${mode.name}'),
                  label: mode.label,
                  icon: [
                    Icons.train_outlined,
                    Icons.directions_car_outlined,
                    Icons.alt_route,
                  ][mode.index],
                  selected: draft.transport == mode,
                  onTap: () => update((c) => c.copyWith(transport: mode)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 28),
        Text(
          '片道移動時間の上限：${draft.maxMinutes}分',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Slider(
          key: const ValueKey('travel-time'),
          value: draft.maxMinutes.clamp(30, 240).toDouble(),
          min: 30,
          max: 240,
          divisions: 14,
          label: '${draft.maxMinutes}分',
          onChanged: (value) =>
              update((c) => c.copyWith(maxMinutes: value.round())),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text('30分'), Text('240分')],
        ),
        if (draft.maxMinutes > 240 || draft.maxMinutes < 30)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '保存済みの移動時間が設定範囲外です。30〜240分で選び直してください。',
              style: TextStyle(color: Colors.red),
            ),
          ),
        const SizedBox(height: 12),
        const Text('公共交通では距離よりも移動時間を重視します。', style: TextStyle(fontSize: 12)),
      ],
    );
  }
}

class ScheduleStepPage extends HookConsumerWidget {
  const ScheduleStepPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(searchDraftProvider);
    void update(SearchConditions Function(SearchConditions) change) => ref
        .read(searchDraftProvider.notifier)
        .replace(change(ref.read(searchDraftProvider)));
    final today = DateUtils.dateOnly(DateTime.now());
    final resolved = draft.resolveDate();
    final lastDay = DateTime(today.year + 10, 12, 31);
    final calendarDate = resolved.isBefore(today)
        ? today
        : resolved.isAfter(lastDay)
        ? lastDay
        : resolved;
    return _StepLayout(
      title: 'いつ、どのくらい旅する？',
      subtitle: '過ごせる時間と予算から、旅の輪郭を。',
      children: [
        const Text('旅行日', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final choice in DateChoice.values)
              ChoiceChip(
                key: ValueKey('date-${choice.name}'),
                label: Text(['明日', '次の週末', '日付指定'][choice.index]),
                selected: draft.dateChoice == choice,
                onSelected: (_) => update(
                  (c) => c.copyWith(
                    dateChoice: choice,
                    fixedDate: choice == DateChoice.fixed && c.fixedDate == null
                        ? today
                        : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${resolved.year}年${resolved.month}月${resolved.day}日',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (draft.dateChoice == DateChoice.fixed) ...[
          if (draft.validate()?.contains('日付') == true)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '過去の日付です。旅行日を選び直してください。',
                style: TextStyle(color: Colors.red),
              ),
            ),
          CalendarDatePicker(
            key: ValueKey('calendar-${draft.fixedDate}'),
            initialDate: calendarDate,
            firstDate: today,
            lastDate: lastDay,
            onDateChanged: (date) => update((c) => c.copyWith(fixedDate: date)),
          ),
        ],
        const SizedBox(height: 28),
        const Text('旅行期間', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final length in TripLength.values)
              ChoiceChip(
                label: Text(length.label),
                selected: draft.length == length,
                onSelected: (_) => update((c) => c.copyWith(length: length)),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          '総予算上限：${draft.budget}円',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text('交通費・食事・体験・宿泊など、旅行全体の上限です。', style: TextStyle(fontSize: 12)),
        Slider(
          key: const ValueKey('total-budget'),
          value: draft.budget.toDouble(),
          min: 1000,
          max: 100000,
          divisions: 99,
          label: '${draft.budget}円',
          onChanged: (value) =>
              update((c) => c.copyWith(budget: value.round())),
        ),
      ],
    );
  }
}

class CompanyStepPage extends HookConsumerWidget {
  const CompanyStepPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(searchDraftProvider);
    void update(SearchConditions Function(SearchConditions) change) => ref
        .read(searchDraftProvider.notifier)
        .replace(change(ref.read(searchDraftProvider)));
    return _StepLayout(
      title: '誰と、どんな条件で？',
      subtitle: '一緒に出かける人と、歩くペースを教えてください。',
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final company in Company.values)
                SizedBox(
                  width: (constraints.maxWidth - 12) / 2,
                  child: _SelectionCard(
                    key: ValueKey('company-${company.name}'),
                    label: ['ひとり旅', '友達', 'カップル', '家族'][company.index],
                    icon: [
                      Icons.person_outline,
                      Icons.group_outlined,
                      Icons.favorite_outline,
                      Icons.family_restroom,
                    ][company.index],
                    selected: draft.company == company,
                    onTap: () => update((c) => c.copyWith(company: company)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ExpansionTile(
          key: const ValueKey('walking-options'),
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          title: const Text('さらに細かく設定'),
          subtitle: Text('徒歩負担：${['少なめ', '普通', '多め'][draft.walking.index]}'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final walking in Walking.values)
                    ChoiceChip(
                      label: Text(['少なめ', '普通', '多め'][walking.index]),
                      selected: draft.walking == walking,
                      onSelected: (_) =>
                          update((c) => c.copyWith(walking: walking)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ],
    );
  }
}
