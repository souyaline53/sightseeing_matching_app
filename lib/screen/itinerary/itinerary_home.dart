import '../../model/transport.dart';
import '../../model/search_settings.dart';
import '../../state/app_tab.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/material.dart';
import '../../model/experience.dart';
import '../../state/trip_state.dart';
import '../../state/trip_library_state.dart';
import 'itinerary_editor.dart';

class ItineraryHome extends StatelessWidget {
  const ItineraryHome({super.key});
  @override
  Widget build(BuildContext context) => const ItineraryEditor();
}

class PlanScreen extends HookConsumerWidget {
  final String? tripId;
  final List<Experience> stops;
  final String origin;
  final DateTime? date;
  final bool publicTransport, demo;
  final SearchConditions conditions;
  const PlanScreen({
    super.key,
    this.tripId,
    required this.stops,
    required this.origin,
    required this.date,
    required this.publicTransport,
    required this.demo,
    required this.conditions,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref
        .watch(tripLibraryProvider)
        .value
        ?.plans
        .where((p) => p.id == tripId)
        .firstOrNull;
    final livePlan = demo ? null : plan;
    final stops = livePlan?.stops ?? this.stops;
    final origin = livePlan?.origin ?? this.origin;
    final date = livePlan == null ? this.date : livePlan.travelDate;
    final publicTransport = livePlan?.publicTransport ?? this.publicTransport;
    final conditions = livePlan?.conditions ?? this.conditions;
    return Scaffold(
      appBar: AppBar(title: Text(demo ? 'デモ用の旅程' : 'マイプラン')),
      floatingActionButton: demo
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                if (tripId != null) {
                  ref.read(tripProvider.notifier).openPlan(tripId!);
                }
                ref.read(appTabProvider.notifier).select(AppTab.itinerary);
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              icon: const Icon(Icons.route_outlined),
              label: const Text('旅を組み立てる'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 110),
        children: [
          Text(
            date == null
                ? '旅行日未確定 · $origin 発'
                : '${date.month}月${date.day}日 · $origin 発',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            '${conditions.length.label} · 総予算${conditions.budget}円以内 · ${conditions.transport.label}',
          ),
          Text(
            '片道${conditions.maxMinutes}分以内 · 徒歩${conditions.walking.label} · ${conditions.company.label}',
          ),
          const Text(
            '下記は保存した訪問順です。予算・移動上限・旅行期間を満たすかは未検証です。複数日でも宿泊や日別の割当は行いません。',
            style: TextStyle(fontSize: 12),
          ),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '交通情報の確認状態は各区間に表示します。\n旅行日・運休日・臨時変更を公式情報で確認してください。',
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
            if (publicTransport &&
                i > 0 &&
                livePlan != null &&
                livePlan.transportSelections.any(
                  (s) => s.from == stops[i - 1].id && s.to == stops[i].id,
                ))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Builder(
                    builder: (context) {
                      final s = livePlan.transportSelections.firstWhere(
                        (s) => s.from == stops[i - 1].id && s.to == stops[i].id,
                      );
                      return Text(
                        '選択した便：${s.data['selectedTripId']}\n${s.data['boardingStopId']} ${transportTime(s.data['departureMinutes'] as int?)} → ${s.data['alightingStopId']} ${transportTime(s.data['arrivalMinutes'] as int?)}\n徒歩 ${s.data['walkingMinutesBefore'] ?? '未確認'}分 / ${s.data['walkingMinutesAfter'] ?? '未確認'}分\n${verificationLabel(s.data['verificationStatus'] as String? ?? 'unverified')}\n選択時点の控えです。編集画面で最新情報を確認してください。',
                      );
                    },
                  ),
                ),
              )
            else if (publicTransport)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('交通便は未選択です。旅程編集画面で登録済みの便を選んでください。'),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '車で移動 · ${i == 0 ? origin : stops[i - 1].area} → ${stops[i].area}\n所要時間・費用は未登録です',
                  ),
                ),
              ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(stops[i].title),
              subtitle: Text(
                '${stops[i].area} · 滞在 ${livePlan?.stayMinutes[stops[i].id] ?? stops[i].minutes}分',
              ),
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
