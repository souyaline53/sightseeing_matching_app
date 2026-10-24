import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../model/experience.dart';
import '../../state/trip_state.dart';
import '../../widgets/travel_photo.dart';
import '../recommendation/experience_detail.dart';

class ItineraryHome extends HookConsumerWidget {
  const ItineraryHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider);
    final controller = ref.read(tripProvider.notifier);
    void addDestination() => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '旅に体験を追加',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Text('保存した体験を先に表示しています。'),
          for (final e in [
            ...trip.saved,
            ...experiences.where((e) => !trip.contains(e)),
          ])
            ListTile(
              title: Text(e.title),
              subtitle: Text(
                '${e.area} · ${trip.contains(e) ? '保存済み' : e.category}',
              ),
              trailing: Icon(trip.stops.contains(e) ? Icons.check : Icons.add),
              onTap: () {
                controller.addStop(e);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
    void showPlan(bool demo) {
      final stops = List<Experience>.of(
        demo ? experiences.take(3) : trip.stops,
      );
      if (stops.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('訪問先を追加してください。')));
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => PlanScreen(
            stops: stops,
            origin: trip.origin.trim().isEmpty ? '札幌駅' : trip.origin.trim(),
            date: trip.date,
            publicTransport: trip.publicTransport,
            demo: demo,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('自分だけの旅を')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            '気になる、をつないで。',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('明日の小さな冒険を、ここから。'),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: trip.date,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 730)),
                helpText: '旅行日を選択',
                cancelText: 'キャンセル',
                confirmText: '決定',
              );
              if (date != null) controller.setDate(date);
            },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(
              '${trip.date.year}年${trip.date.month}月${trip.date.day}日 · 日帰り',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: trip.origin,
            decoration: const InputDecoration(
              labelText: '出発地',
              prefixIcon: Icon(Icons.trip_origin),
            ),
            onChanged: controller.setOrigin,
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.train_outlined),
                label: Text('公共交通'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.directions_car_outlined),
                label: Text('車'),
              ),
            ],
            selected: {trip.publicTransport},
            onSelectionChanged: (value) => controller.setTransport(value.first),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '訪問する体験',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Text('${trip.stops.length}件'),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '右端をドラッグして、好きな順番に。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (trip.stops.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'まだ訪問先がありません。\n「発見する」で保存するか、下のボタンから追加しましょう。',
                textAlign: TextAlign.center,
              ),
            ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: trip.stops.length,
            onReorder: controller.reorder,
            itemBuilder: (context, i) {
              final e = trip.stops[i];
              return Card(
                key: ValueKey(e.id),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 62,
                        height: 78,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: TravelPhoto(e),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () => showExperience(context, e),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${i + 1}. ${e.title}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${e.area} · 約${e.minutes}分',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '訪問先から削除',
                        onPressed: () => controller.removeStop(e),
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: addDestination,
            icon: const Icon(Icons.add),
            label: const Text('体験を追加する'),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: () => showPlan(false),
            child: const Text('自分で組み立てる'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => showPlan(true),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('AIに提案してもらう'),
          ),
          const SizedBox(height: 8),
          const Text(
            'AI提案はモックの3件を使ったデモ用の旅程です。\n保存や設定はアプリ起動中のみ保持されます。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class PlanScreen extends HookConsumerWidget {
  final List<Experience> stops;
  final String origin;
  final DateTime date;
  final bool publicTransport, demo;
  const PlanScreen({
    super.key,
    required this.stops,
    required this.origin,
    required this.date,
    required this.publicTransport,
    required this.demo,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final legs = sampleTransit(origin, stops);
    return Scaffold(
      appBar: AppBar(title: Text(demo ? 'デモ用の旅程' : 'マイプラン')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(
            '${date.month}月${date.day}日 · $origin 発',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'サンプル時刻・実際の運行情報ではありません\n移動時間・料金・訪問可否を含む、画面確認用の旅程です。',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (demo)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('デモ用の旅程：AIには接続していません。'),
            ),
          for (var i = 0; i < stops.length; i++) ...[
            const SizedBox(height: 16),
            if (publicTransport)
              TransitCard(leg: legs[i])
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '車で移動 · ${i == 0 ? origin : stops[i - 1].area} → ${stops[i].area}\n所要約60分・費用約1,000円（ダミー）',
                  ),
                ),
              ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(stops[i].title),
              subtitle: Text('${stops[i].area} · 滞在目安 ${stops[i].minutes}分'),
            ),
          ],
          const SizedBox(height: 20),
          const Card(
            color: Color(0xfffff0d6),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '最終便に注意\n復路は未検索です。最終便・運休日・乗換時間を必ず確認し、余裕のある帰路を確保してください。サンプルの接続や日帰りの実現性は保証していません。',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TransitCard extends HookConsumerWidget {
  final TransitLeg leg;
  const TransitCard({super.key, required this.leg});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_transit, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  leg.mode,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(),
          Text(
            '${leg.departure} ${leg.from}\n   ↓\n${leg.arrival} ${leg.to}',
            style: const TextStyle(height: 1.7),
          ),
          const SizedBox(height: 10),
          Text(
            '${leg.transfer}\n${leg.walking}\n推定交通費：${leg.fare}',
            style: const TextStyle(fontSize: 12, height: 1.7),
          ),
        ],
      ),
    ),
  );
}
