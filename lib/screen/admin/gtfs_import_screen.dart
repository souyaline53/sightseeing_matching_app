import '../../service/transport/transport_admin_api.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../service/cloud/cloud_services.dart';
import '../../service/transport/txt_picker.dart';
import '../../service/transport/gtfs_txt_file.dart';

class GtfsImportScreen extends ConsumerStatefulWidget {
  const GtfsImportScreen({super.key});
  @override
  ConsumerState<GtfsImportScreen> createState() => _State();
}

class _State extends ConsumerState<GtfsImportScreen> {
  final feed = TextEditingController();
  List<GtfsTxtFile>? files;
  int uploaded = 0;
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
        'transport_imports/${cloud.auth.currentUser!.uid}/${feed.text}/${DateTime.now().microsecondsSinceEpoch}';
    uploaded = 0;
    for (final file in files!) {
      await cloud.storage
          .ref('$path/${file.name}')
          .putData(file.bytes, SettableMetadata(contentType: 'text/plain'));
      if (mounted) setState(() => uploaded++);
    }
    final response = await transportFunctions()
        .httpsCallable(
          'importTransport',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
        )
        .call({
          'action': 'preview',
          'feedId': feed.text,
          'sourceDirectory': path,
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
          files = null;
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
          'UTF-8の.txtファイル一式をまとめて選択してください。更新時も同じフィードIDを使います。1ファイル50MiB・合計100MiBまで。',
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
                  final picked = await pickGtfsTxtFiles();
                  if (mounted && picked != null) {
                    setState(() {
                      files = picked;
                      preview = null;
                    });
                  }
                }),
          child: Text(
            files == null
                ? 'GTFS .txtファイルをまとめて選択'
                : '${files!.length}ファイル選択済み（${files!.fold<int>(0, (n, f) => n + f.bytes.length)} bytes）',
          ),
        ),
        FilledButton(
          onPressed: busy || files == null ? null : upload,
          child: const Text('アップロード・検証・プレビュー'),
        ),
        ExpansionTile(
          title: const Text('アップロードする標準ファイル名の一覧'),
          initiallyExpanded: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '別の名前で提供された場合は、内容を確認して下記の名前へ変更してください。列名・ID・ファイル内容は変更しません。異なる事業者やダイヤ版のファイルを混ぜず、一式を同時に選んでください。',
              ),
            ),
            for (final entry in gtfsFileDescriptions.entries)
              ListTile(
                dense: true,
                title: SelectableText(entry.key),
                subtitle: Text(entry.value),
                trailing: files?.any((f) => f.name == entry.key) == true
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
              ),
          ],
        ),
        if (files != null)
          for (final f in files!)
            Text(
              '${f.name}（${f.bytes.length} bytes）${gtfsFileDescriptions.containsKey(f.name) ? '' : '：未対応拡張。原本保存・検証時に警告'}',
            ),
        if (busy) ...[
          const LinearProgressIndicator(),
          Text('アップロード $uploaded / ${files?.length ?? 0}・サーバー検証／登録中'),
        ],
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
