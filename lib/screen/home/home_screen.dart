import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/trip_plan.dart';
import '../../model/search_settings.dart';
import '../../state/app_tab.dart';
import '../../state/discovery_state.dart';
import '../../state/settings_state.dart';
import '../../state/trip_library_state.dart';
import '../../widgets/travel_photo.dart';
import '../itinerary/itinerary_home.dart';

class HomeScreen extends HookConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(tripLibraryProvider).requireValue;
    final settings = ref.watch(settingsProvider).requireValue;
    final chosenId = useState<String?>(null);
    final today = useState(DateUtils.dateOnly(DateTime.now()));
    useEffect(() {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day + 1);
      final timer = Timer(
        midnight.difference(now),
        () => today.value = DateUtils.dateOnly(DateTime.now()),
      );
      return timer.cancel;
    }, [today.value]);
    final upcoming = library.upcoming(today.value);
    TripState? plan;
    if (upcoming.isNotEmpty) {
      plan = upcoming.firstWhere(
        (p) => p.id == chosenId.value,
        orElse: () => upcoming.first,
      );
    }
    void search({bool last = false}) {
      ref
          .read(searchDraftProvider.notifier)
          .replace(
            last
                ? settings.lastSearch!.conditions
                : settings.profile.defaults(),
          );
      ref.read(discoveryProvider.notifier).beginSearch();
    }

    Widget searchButton() => SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => search(),
        icon: const Icon(Icons.explore_outlined),
        label: const Text('新しい旅を探す'),
      ),
    );
    Widget previousSearch() => settings.lastSearch == null
        ? const SizedBox.shrink()
        : TextButton(
            onPressed: () => search(last: true),
            child: const Text('前回の条件で探す'),
          );
    if (plan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('TABISAKI')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 76,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                const Text(
                  'まだ知らないワクワクを、\n自分だけの旅に。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 27,
                    height: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                const Text('まだ旅行の予定はありません'),
                const SizedBox(height: 28),
                searchButton(),
                previousSearch(),
              ],
            ),
          ),
        ),
      );
    }
    final trip = plan;
    final dateLabel = trip.travelDate == null
        ? '日程未定'
        : '${trip.travelDate!.year}年${trip.travelDate!.month}月${trip.travelDate!.day}日';
    return Scaffold(
      appBar: AppBar(
        title: const Text('TABISAKI'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '旅行計画の操作',
            onSelected: (value) async {
              if (value != 'delete') return;
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('旅行計画を削除しますか？'),
                  content: Text('「${trip.displayTitle}」を削除します。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('キャンセル'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('削除'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                ref.read(tripLibraryProvider.notifier).delete(trip.id);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'delete', child: Text('この旅行計画を削除')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Text(
            '次の旅行のしおり',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          if (upcoming.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: DropdownButtonFormField<String>(
                initialValue: trip.id,
                key: ValueKey('home-trip-${trip.id}'),
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'ほかの旅行計画に切り替える'),
                items: [
                  for (final p in upcoming)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        p.displayTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => chosenId.value = id,
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 220,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TravelPhoto(trip.stops.first),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateLabel,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          trip.displayTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            fontWeight: FontWeight.bold,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '出発地：${trip.origin}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '移動手段：${trip.conditions.transport.label} · ${trip.conditions.length.label}',
          ),
          const SizedBox(height: 12),
          const Text(
            '訪問順をまとめたしおりです。訪問時刻は未設定で、交通経路・運行情報は未確認です。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 22),
          for (var i = 0; i < trip.stops.length; i++) ...[
            if (trip.publicTransport)
              Padding(
                padding: const EdgeInsets.only(left: 42, bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.directions_transit_outlined, size: 17),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${i == 0 ? trip.origin : trip.stops[i - 1].area} → ${trip.stops[i].area}\n経路未確認',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 32,
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (i < trip.stops.length - 1)
                          Expanded(
                            child: Container(
                              width: 1,
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      trip.stops[i].title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      trip.stops[i].area,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 64,
                                  height: 78,
                                  child: TravelPhoto(trip.stops[i]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => PlanScreen(
                  stops: trip.stops,
                  origin: trip.origin,
                  date: trip.travelDate,
                  publicTransport: trip.publicTransport,
                  demo: false,
                  conditions: trip.conditions,
                ),
              ),
            ),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('旅のしおりを開く'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              ref.read(tripLibraryProvider.notifier).select(trip.id);
              ref.read(appTabProvider.notifier).select(AppTab.itinerary);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('旅程を編集する'),
          ),
          const SizedBox(height: 24),
          searchButton(),
          previousSearch(),
        ],
      ),
    );
  }
}
