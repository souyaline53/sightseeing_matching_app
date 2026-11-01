import '../../service/transport/transport_admin_api.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../service/cloud/cloud_services.dart';
import '../../service/transport/zip_picker.dart';

class GtfsImportScreen extends ConsumerStatefulWidget {
  const GtfsImportScreen({super.key});
  @override
  ConsumerState<GtfsImportScreen> createState() => _State();
}

class _State extends ConsumerState<GtfsImportScreen> {
  final feed = TextEditingController();
  Uint8List? bytes;
  Map<String, dynamic>? preview;
  bool busy = false;
  String message = '';
  @override
  void dispose() {
    feed.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() task) async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> upload() => run(() async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,60}$').hasMatch(feed.text)) {
      throw StateError('フィードIDを英数字・_・-で入力してください');
    }
    final cloud = await ref.read(cloudServicesProvider.future);
    cloud.requireAdmin();
    final path =
        'transport_imports/${cloud.auth.currentUser!.uid}/${feed.text}/${DateTime.now().microsecondsSinceEpoch}.zip';
    await cloud.storage
        .ref(path)
        .putData(bytes!, SettableMetadata(contentType: 'application/zip'));
    final response = await transportFunctions()
        .httpsCallable(
          'importTransport',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
        )
        .call({
          'action': 'preview',
          'feedId': feed.text,
          'sourceFilePath': path,
        });
    if (mounted) {
      setState(() => preview = Map<String, dynamic>.from(response.data as Map));
    }
  });
  Future<void> commit() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('新バージョンを登録・有効化しますか？'),
        content: const Text('プレビューの件数・警告を確認してください。旧版と手動データは保持されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('承認して登録'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    await run(() async {
      final cloud = await ref.read(cloudServicesProvider.future);
      cloud.requireAdmin();
      await transportFunctions()
          .httpsCallable(
            'importTransport',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
          )
          .call({
            'action': 'commit',
            'feedId': feed.text,
            'versionId': preview!['versionId'],
            'expectedActiveVersionId': preview!['expectedActiveVersionId'],
          });
      if (mounted) {
        setState(() {
          message = '登録・有効化が完了しました';
          preview = null;
          bytes = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('GTFSインポート')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '同じフィードの更新には同じフィードIDを指定してください。ZIP直下にUTF-8のGTFSファイルを配置します（最大20MiB）。',
        ),
        TextField(
          controller: feed,
          enabled: !busy && preview == null,
          decoration: const InputDecoration(labelText: 'フィードID（例 yutetsu）'),
        ),
        OutlinedButton(
          onPressed: busy
              ? null
              : () => run(() async {
                  final picked = await pickGtfsZip();
                  if (mounted && picked != null) {
                    setState(() {
                      bytes = picked;
                      preview = null;
                    });
                  }
                }),
          child: Text(
            bytes == null
                ? 'GTFS ZIPファイルを選択'
                : 'ZIP選択済み（${bytes!.length} bytes）',
          ),
        ),
        FilledButton(
          onPressed: busy || bytes == null ? null : upload,
          child: const Text('アップロード・検証・プレビュー'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (preview != null) ...[
          for (final entry in {
            'agencyNames': '交通事業者',
            'validFrom': '有効開始',
            'validTo': '有効終了',
            'routes': '路線数',
            'stops': '停留所数',
            'trips': '便数',
            'stopTimes': '発着時刻件数',
            'fares': '運賃件数',
            'new': '新規予定',
            'updated': '更新候補（同一ID）',
            'retired': '廃止候補（旧版保持）',
          }.entries)
            Text('${entry.value}：${preview![entry.key]}'),
          for (final error in preview!['errors'] as List)
            Text(
              'エラー：$error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final warning in preview!['warnings'] as List)
            Text('警告：$warning'),
          FilledButton(
            onPressed: busy || (preview!['errors'] as List).isNotEmpty
                ? null
                : commit,
            child: const Text('内容を確認して登録へ'),
          ),
        ],
        if (message.isNotEmpty) SelectableText(message),
      ],
    ),
  );
}
