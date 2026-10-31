import 'transport_admin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/catalog_record.dart';
import '../../service/cloud/catalog_admin_service.dart';
import '../../service/cloud/cloud_services.dart';
import '../../service/cloud/image_optimization_service.dart';
import '../../state/account_state.dart';
import '../../widgets/settings_actions.dart';
import 'catalog_edit_screen.dart';
import 'user_type_panel.dart';

class AdminMenuScreen extends HookConsumerWidget {
  const AdminMenuScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider);
    final tabs = useTabController(initialLength: 3);
    useListenable(tabs);
    final busy = useState(false);
    final progress = useState('');
    final isAdmin = ref.watch(isAdminProvider);
    Future<void> open(CatalogKind kind, [CatalogRecord? record]) async {
      if (busy.value) return;
      busy.value = true;
      try {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => CatalogEditScreen(kind: kind, record: record),
          ),
        );
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> optimizeImages() async {
      if (busy.value) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('既存画像を200KB以下に最適化'),
          content: const Text(
            '観光地・投稿の大きな画像を一度取得し、200KB以下の画像を作成して表示URLを更新します。最適化済み画像は再作成しません。旧画像は残します。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('最適化する'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      busy.value = true;
      try {
        final result = await ref.read(imageOptimizationServiceProvider).run((
          value,
        ) {
          if (context.mounted) progress.value = value;
        });
        if (context.mounted) {
          showMessage(
            context,
            '${result.optimized}枚を最適化・${result.unchanged}枚は最適化済み・失敗${result.failures.length}件${result.failures.isEmpty ? '' : '。ルールと通信を確認し、再実行してください。'}',
          );
        }
      } catch (_) {
        if (context.mounted) {
          showMessage(context, '画像を最適化できませんでした。ルール・権限・通信を確認してください。');
        }
      } finally {
        if (context.mounted) {
          busy.value = false;
          progress.value = '';
        }
      }
    }

    final authorized = isAdmin && account.identity.emailVerified;
    return PopScope(
      canPop: !busy.value,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('管理者メニュー'),
          actions: [
            if (authorized)
              IconButton(
                tooltip: '交通マスター・時刻表',
                icon: const Icon(Icons.departure_board),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const TransportAdminScreen(),
                  ),
                ),
              ),
            if (authorized)
              IconButton(
                tooltip: '既存画像を200KB以下に最適化',
                onPressed: busy.value ? null : optimizeImages,
                icon: const Icon(Icons.compress_outlined),
              ),
          ],
          bottom: authorized
              ? TabBar(
                  controller: tabs,
                  tabs: const [
                    Tab(text: '観光地情報'),
                    Tab(text: '交通時刻表'),
                    Tab(text: 'ユーザー属性'),
                  ],
                )
              : null,
        ),
        floatingActionButton: authorized && tabs.index == 0
            ? FloatingActionButton.extended(
                onPressed: busy.value
                    ? null
                    : () => open(CatalogKind.sightseeing),
                icon: const Icon(Icons.add),
                label: const Text('追加'),
              )
            : null,
        body: !authorized
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    isAdmin
                        ? 'メールアドレスの確認を完了し、プロフィールで「確認状態を更新」を押してください。'
                        : '管理者アカウントでログインしてください。',
                  ),
                ),
              )
            : Column(
                children: [
                  if (progress.value.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          Text(progress.value),
                        ],
                      ),
                    ),
                  Expanded(
                    child: TabBarView(
                      controller: tabs,
                      children: [
                        for (final kind in CatalogKind.values)
                          _RecordsList(
                            kind: kind,
                            busy: busy.value,
                            onEdit: (record) => open(kind, record),
                          ),
                        const TransportAdminScreen(embedded: true),
                        const UserTypePanel(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RecordsList extends HookConsumerWidget {
  final CatalogKind kind;
  final bool busy;
  final void Function(CatalogRecord) onEdit;
  const _RecordsList({
    required this.kind,
    required this.busy,
    required this.onEdit,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deleting = useState(false);
    return ref
        .watch(adminRecordsProvider(kind))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('クラウドデータを読み込めませんでした。\n$error'),
                  TextButton(
                    onPressed: () => ref.invalidate(adminRecordsProvider(kind)),
                    child: const Text('再読み込み'),
                  ),
                ],
              ),
            ),
          ),
          data: (records) => records.isEmpty
              ? const Center(child: Text('まだ登録されていません。＋から追加できます。'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: records.length,
                  itemBuilder: (context, i) {
                    final record = records[i];
                    return ListTile(
                      title: Text(record.title),
                      subtitle: Text(record.id),
                      onTap: busy || deleting.value
                          ? null
                          : () => onEdit(record),
                      trailing: IconButton(
                        tooltip: '削除',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: busy || deleting.value
                            ? null
                            : () async {
                                final yes = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('削除しますか？'),
                                    content: Text(
                                      '「${record.title}」とその写真をクラウドから削除します。既存の旅程の控えは残ります。',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('キャンセル'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('削除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (yes != true || !context.mounted) return;
                                deleting.value = true;
                                try {
                                  final failed = await ref
                                      .read(catalogAdminServiceProvider)
                                      .delete(record);
                                  if (context.mounted) {
                                    showMessage(
                                      context,
                                      failed.isEmpty
                                          ? '削除しました。'
                                          : '情報は削除済みです。一部の写真の削除に失敗しました。Storageを確認してください。',
                                    );
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    showMessage(
                                      context,
                                      '削除できませんでした。通信と権限を確認してください。',
                                    );
                                  }
                                } finally {
                                  if (context.mounted) deleting.value = false;
                                }
                              },
                      ),
                    );
                  },
                ),
        );
  }
}
