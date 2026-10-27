import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/search_settings.dart';
import '../../data/departure_places.dart';
import '../../state/settings_state.dart';
import '../../state/discovery_state.dart';
import '../../state/conditions_step_state.dart';
import '../../widgets/departure_map.dart';

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
    key: ValueKey(title),
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
        const SizedBox(height: 24),
        ...children,
      ],
    ),
  );
}

class _SelectionCard extends HookConsumerWidget {
  final String label;
  final String? description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _SelectionCard({
    super.key,
    required this.label,
    this.description,
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
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
            child: description == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: colors.primary, size: 30),
                      const SizedBox(height: 10),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(icon, color: colors.primary, size: 34),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              description!,
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
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
    void select(String name, {bool confirm = false}) {
      if (ref.read(discoveryProvider).step != 1 ||
          ref.read(conditionsStepProvider) != 0) {
        return;
      }
      ref
          .read(searchDraftProvider.notifier)
          .replace(ref.read(searchDraftProvider).copyWith(origin: name));
      if (confirm && name.trim().isNotEmpty) {
        FocusScope.of(context).unfocus();
        ref.read(conditionsStepProvider.notifier).nextFrom(0);
      }
    }

    final matches = findDepartures(draft.origin);
    return _StepLayout(
      title: 'どこから旅を始める？',
      subtitle: '候補はタップで確定。地図のピンは選んでから確認できます。',
      children: [
        TextField(
          key: const ValueKey('search-origin'),
          controller: origin,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '駅名・地域名を検索',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => select(v),
        ),
        const SizedBox(height: 12),
        const Text('よく使う出発地', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final name in {
              '札幌駅',
              '小樽駅',
              '新千歳空港',
              ref.read(settingsProvider).requireValue.profile.origin,
            })
              ActionChip(
                key: ValueKey('origin-chip-$name'),
                label: Text(name),
                onPressed: () => select(name, confirm: true),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          '検索候補（ローカルのサンプル）',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final p in matches.take(5))
          ListTile(
            key: ValueKey('origin-result-${p.id}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              p.bus ? Icons.directions_bus_outlined : Icons.train_outlined,
            ),
            title: Text(p.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => select(p.name, confirm: true),
          ),
        if (draft.origin.trim().isNotEmpty &&
            !matches.any((p) => p.name == draft.origin.trim()))
          ListTile(
            key: const ValueKey('origin-free-text'),
            contentPadding: EdgeInsets.zero,
            title: Text('「${draft.origin.trim()}」を出発地にする'),
            subtitle: const Text('地域名の直接入力（地図座標・経路は未確認）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => select(draft.origin.trim(), confirm: true),
          ),
        const SizedBox(height: 12),
        DepartureMap(selected: draft.origin, onSelect: (p) => select(p.name)),
        const SizedBox(height: 10),
        Text(
          '選択中の出発地：${draft.origin.isEmpty ? '未選択' : draft.origin}',
          key: const ValueKey('selected-origin'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'ピンの位置・駅・バス停候補はサンプルです。実際の運行情報ではありません。',
          style: TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}

class TransportStepPage extends HookConsumerWidget {
  const TransportStepPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(searchDraftProvider);
    return _StepLayout(
      title: 'どうやって旅する？',
      subtitle: 'いつもの移動手段でも、違う旅のかたちでも。',
      children: [
        for (final mode in TravelMode.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _SelectionCard(
              key: ValueKey('travel-${mode.name}'),
              label: ['公共交通で旅する', '車で旅する', 'どちらでもOK'][mode.index],
              description: [
                '電車やバスを使って、車がなくても旅へ。',
                '自分のペースで、寄り道も自由に。',
                '体験に合わせて、移動の選択肢を広げる。',
              ][mode.index],
              icon: [
                Icons.train_outlined,
                Icons.directions_car_outlined,
                Icons.alt_route,
              ][mode.index],
              selected: draft.transport == mode,
              onTap: () {
                if (ref.read(discoveryProvider).step != 1 ||
                    ref.read(conditionsStepProvider) != 1) {
                  return;
                }
                ref
                    .read(searchDraftProvider.notifier)
                    .replace(
                      ref.read(searchDraftProvider).copyWith(transport: mode),
                    );
                ref.read(conditionsStepProvider.notifier).nextFrom(1);
              },
            ),
          ),
      ],
    );
  }
}

class DetailsStepPage extends HookConsumerWidget {
  const DetailsStepPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(searchDraftProvider);
    void update(SearchConditions Function(SearchConditions) change) => ref
        .read(searchDraftProvider.notifier)
        .replace(change(ref.read(searchDraftProvider)));
    return _StepLayout(
      title: '旅の条件を決めよう',
      subtitle: 'そのままでも大丈夫。スキップすると開始時の詳細条件を使います。',
      children: [
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
          onChanged: (v) => update((c) => c.copyWith(maxMinutes: v.round())),
        ),
        if (draft.maxMinutes > 240)
          const Text(
            '保存済みの移動時間を保持しています。変更する場合は30〜240分で選べます。',
            style: TextStyle(fontSize: 12),
          ),
        const SizedBox(height: 20),
        const Text('旅行期間', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
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
        const SizedBox(height: 24),
        Text(
          '総予算上限：${draft.budget}円',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text('交通費・食事・体験・宿泊を含む旅行全体の上限です。', style: TextStyle(fontSize: 12)),
        Slider(
          key: const ValueKey('total-budget'),
          value: draft.budget.toDouble(),
          min: 1000,
          max: 100000,
          divisions: 99,
          label: '${draft.budget}円',
          onChanged: (v) => update((c) => c.copyWith(budget: v.round())),
        ),
        const SizedBox(height: 20),
        const Text('同行者', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
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
                    label: ['ひとり', '友達', 'カップル', '家族'][company.index],
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
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          '条件はサンプルの推薦順位に反映します。旅行日は旅程画面で別途指定し、時刻表・料金・利用可否は未検証です。',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
