import '../../service/transport/transport_admin_api.dart';
import 'transport_sample_screen.dart';
import 'transport_stop_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'gtfs_import_screen.dart';
import '../../model/admin_transport_fields.dart';
import 'transport_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../repository/transport_repository.dart';
import '../../service/cloud/cloud_services.dart';

class TransportAdminScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const TransportAdminScreen({super.key, this.embedded = false});
  @override
  ConsumerState<TransportAdminScreen> createState() => _TransportAdminState();
}

class _TransportAdminState extends ConsumerState<TransportAdminScreen> {
  String collection = 'transport_agencies';
  late Future<List<Map<String, dynamic>>> records;
  String? scope, cursor;
  bool hasMore = false;
  bool get scoped => [
    'transport_routes',
    'transport_stops',
    'transport_trips',
    'transport_fares',
  ].contains(collection);
  Future<void> chooseScope() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => TransportStopPicker(
        manualOnly: true,
        selectAgency: collection == 'transport_routes',
        selectRoute: collection != 'transport_routes',
      ),
    );
    if (id != null && mounted) {
      setState(() {
        scope = id;
        cursor = null;
        records = load();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    records = load();
  }

  Future<List<Map<String, dynamic>>> load() async {
    final cloud = await ref.read(cloudServicesProvider.future);
    cloud.requireAdmin();
    if (scoped && scope == null) return [];
    Query<Map<String, dynamic>> q = cloud.firestore.collection(collection);
    if (scoped) {
      q = collection == 'transport_stops'
          ? q.where('routeIds', arrayContains: scope)
          : q.where(
              collection == 'transport_routes' ? 'agencyId' : 'routeId',
              isEqualTo: scope,
            );
    }
    q = q.orderBy(FieldPath.documentId).limit(100);
    if (cursor != null) q = q.startAfter([cursor]);
    final docs = await q.get();
    hasMore = docs.docs.length == 100;
    if (docs.docs.isNotEmpty) cursor = docs.docs.last.id;
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
          if (targetCollection == 'transport_trips') {
            final times =
                (data['stopTimes'] as List)
                    .map((r) => Map<String, dynamic>.from(r as Map))
                    .toList()
                  ..sort(
                    (a, b) =>
                        (a['sequence'] as int).compareTo(b['sequence'] as int),
                  );
            for (final row in times) {
              row['arrivalSeconds'] = (row['arrivalMinutes'] as int?) == null
                  ? null
                  : (row['arrivalMinutes'] as int) * 60;
              row['departureSeconds'] =
                  (row['departureMinutes'] as int?) == null
                  ? null
                  : (row['departureMinutes'] as int) * 60;
              row['pickupType'] = row['pickupAllowed'] == false ? 1 : 0;
              row['dropOffType'] = row['dropoffAllowed'] == false ? 1 : 0;
            }
            data['stopTimes'] = times;
            data['stopIds'] = times.map((r) => r['stopId']).toSet().toList();
            data['firstDepartureMinutes'] = times.first['departureMinutes'];
            data['lastArrivalMinutes'] = times.last['arrivalMinutes'];
            data['firstStopId'] = times.first['stopId'];
            data['lastStopId'] = times.last['stopId'];
          }
          final cloud = await ref.read(cloudServicesProvider.future);
          cloud.requireAdmin();
          final editable = {
            for (final field in transportFields(targetCollection))
              if (data.containsKey(field.key)) field.key: data[field.key],
          };
          await transportFunctions().httpsCallable('saveManualTransport').call({
            'collection': targetCollection,
            'id': id,
            'data': editable,
            'creating': creating,
          });
        },
      ),
    );
    if (mounted) {
      setState(() {
        cursor = null;
        records = load();
      });
    }
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
        ListTile(
          title: const Text('GTFSインポート'),
          leading: const Icon(Icons.upload_file),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GtfsImportScreen()),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TransportSampleScreen()),
          ),
          child: const Text('旧サンプルの削除候補を確認'),
        ),
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
                scope = null;
                cursor = null;
                hasMore = false;
                records = load();
              });
            }
          },
        ),
        if (scoped)
          TextButton(
            onPressed: chooseScope,
            child: Text(scope == null ? '事業者・路線を選択して読み込む' : '選択条件：$scope（変更）'),
          ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('手動マスターの先頭100件を表示。GTFSはインポート画面から更新します。'),
        ),
        ExpansionTile(
          title: const Text('交通データの追加手順'),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '① 事業者 → 停留所 → 路線 → 運行日 → 便 → 運賃の順に登録\n② 登録済みの候補から路線や駅・バス停を選ぶ\n③ 時刻表の行を追加し、停車順と時刻を入力（例 08:10 / 25:10）\n④ 観光地編集で最寄り停留所を追加。徒歩時間不明は空欄\n⑤ 必要に応じて情報源を記録する。',
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
                  if (hasMore)
                    TextButton(
                      onPressed: () => setState(() => records = load()),
                      child: const Text('次の100件'),
                    ),
                  for (final r in snapshot.data!)
                    ListTile(
                      title: Text('${r['name'] ?? r['headsign'] ?? r['id']}'),
                      subtitle: Text('${r['id']}'),
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
  'transport_transfers': '⑦ 乗り場間の乗換接続',
};
