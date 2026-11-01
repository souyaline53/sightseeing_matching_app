import '../../service/transport/transport_admin_api.dart';
import 'package:flutter/material.dart';

/// Inventory only: device-local saved journeys cannot be audited from Firestore.
class TransportSampleScreen extends StatefulWidget {
  const TransportSampleScreen({super.key});
  @override
  State<TransportSampleScreen> createState() => _State();
}

class _State extends State<TransportSampleScreen> {
  String collection = 'transport_trips';
  String? cursor;
  List<Map<String, dynamic>> rows = [];
  bool busy = false;
  String error = '';
  Future<void> load({bool next = false}) async {
    setState(() {
      busy = true;
      error = '';
      if (!next) {
        cursor = null;
        rows = [];
      }
    });
    try {
      final r = await transportFunctions()
          .httpsCallable('transportSampleInventory')
          .call({'collection': collection, 'after': cursor});
      if (mounted) {
        setState(() {
          rows.addAll(
            (r.data['records'] as List).map(
              (x) => Map<String, dynamic>.from(x as Map),
            ),
          );
          cursor = r.data['next'] as String?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('旧サンプルの削除候補')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'sourceType / verificationStatus が sample の既存データだけを抽出します。名称やIDだけでは判定しません。端末に保存された旅程の参照はサーバーから確認できないため、この画面では削除を実行しません。',
        ),
        DropdownButton<String>(
          value: collection,
          isExpanded: true,
          items: [
            for (final c in [
              'transport_agencies',
              'transport_routes',
              'transport_stops',
              'transport_trips',
              'transport_services',
              'transport_fares',
            ])
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: busy
              ? null
              : (v) {
                  if (v != null) {
                    setState(() {
                      collection = v;
                      rows = [];
                      cursor = null;
                    });
                  }
                },
        ),
        FilledButton(
          onPressed: busy ? null : () => load(),
          child: const Text('削除候補を取得'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty) Text(error),
        for (final r in rows)
          ListTile(
            title: Text('${r['name']}'),
            subtitle: SelectableText(
              '${r['id']} / ${r['sourceType']} / ${r['verificationStatus']}',
            ),
          ),
        if (cursor != null)
          TextButton(
            onPressed: busy ? null : () => load(next: true),
            child: const Text('次の100件'),
          ),
      ],
    ),
  );
}
