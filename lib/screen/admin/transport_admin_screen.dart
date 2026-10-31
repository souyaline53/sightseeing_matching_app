import '../../model/admin_transport_fields.dart';
import 'transport_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../repository/transport_repository.dart';
import '../../model/transport.dart';
import '../../service/cloud/cloud_services.dart';

class TransportAdminScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const TransportAdminScreen({super.key, this.embedded = false});
  @override
  ConsumerState<TransportAdminScreen> createState() => _TransportAdminState();
}

class _TransportAdminState extends ConsumerState<TransportAdminScreen> {
  String collection = 'transport_trips';
  late Future<List<Map<String, dynamic>>> records;
  @override
  void initState() {
    super.initState();
    records = load();
  }

  Future<List<Map<String, dynamic>>> load() async {
    final cloud = await ref.read(cloudServicesProvider.future);
    cloud.requireAdmin();
    final docs = await cloud.firestore.collection(collection).limit(100).get();
    return docs.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> edit([
    Map<String, dynamic>? record,
    bool duplicate = false,
  ]) async {
    final targetCollection = collection;
    final creating = record == null || duplicate;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TransportEditDialog(
        collection: targetCollection,
        title: transportCollectionLabels[targetCollection]!,
        record: record,
        duplicate: duplicate,
        onSave: (id, data) async {
          validateTransport(targetCollection, data);
          final cloud = await ref.read(cloudServicesProvider.future);
          cloud.requireAdmin();
          final document = cloud.firestore.collection(targetCollection).doc(id);
          await cloud.firestore.runTransaction((transaction) async {
            final existing = await transaction.get(document);
            if (creating && existing.exists) {
              throw StateError('このIDは既に登録されています');
            }
            if (!creating && !existing.exists) {
              throw StateError('このデータは既に削除されています');
            }
            final now = DateTime.now().toUtc().toIso8601String();
            transaction.set(document, {
              ...?existing.data(),
              ...data,
              'id': id,
              'createdAt': existing.data()?['createdAt'] ?? now,
              'updatedAt': now,
            });
          });
        },
      ),
    );
    if (mounted) setState(() => records = load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded ? null : AppBar(title: const Text('交通マスター・時刻表')),
    floatingActionButton: FloatingActionButton(
      onPressed: edit,
      child: const Icon(Icons.add),
    ),
    body: Column(
      children: [
        DropdownButton<String>(
          value: collection,
          isExpanded: true,
          items: transportCollections
              .map(
                (c) => DropdownMenuItem(
                  value: c,
                  child: Text(transportCollectionLabels[c] ?? c),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                collection = v;
                records = load();
              });
            }
          },
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('先頭100件を表示。サンプル3便は架空の登録例です。複製ボタンから新しいIDで追加できます。'),
        ),
        ExpansionTile(
          title: const Text('交通データの追加手順'),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '① 事業者 → 停留所 → 路線 → 運行日 → 便 → 運賃の順に登録\n② 登録済みの候補から路線や駅・バス停を選ぶ\n③ 時刻表の行を追加し、停車順と時刻を入力（例 08:10 / 25:10）\n④ 観光地編集で最寄り停留所を追加。徒歩時間不明は空欄\n⑤ 実データは情報源と確認状態を記録する。sample_*は登録例です。',
              ),
            ),
          ],
        ),
        Expanded(
          child: FutureBuilder(
            future: records,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('読み込めませんでした：${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                children: [
                  for (final r in snapshot.data!)
                    ListTile(
                      title: Text('${r['name'] ?? r['headsign'] ?? r['id']}'),
                      subtitle: Text(
                        '${r['id']} / ${verificationLabel(r['verificationStatus'] as String? ?? 'unverified')}',
                      ),
                      onTap: () => edit(r),
                      trailing: IconButton(
                        tooltip: '複製して追加',
                        icon: const Icon(Icons.copy_outlined),
                        onPressed: () => edit(r, true),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

const transportCollectionLabels = {
  'transport_agencies': '① 交通事業者',
  'transport_stops': '② 駅・バス停',
  'transport_routes': '③ 路線',
  'transport_services': '④ 運行日・例外日',
  'transport_trips': '⑤ 便・時刻表',
  'transport_fares': '⑥ 区間運賃',
};
