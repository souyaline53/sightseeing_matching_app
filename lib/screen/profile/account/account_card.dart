import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../model/account_profile.dart';
import '../../../state/account_state.dart';
import '../../../widgets/settings_actions.dart';
import 'account_form_screen.dart';

class AccountCard extends HookConsumerWidget {
  const AccountCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider);
    final repository = ref.watch(accountRepositoryProvider);
    final busy = useState(false);
    final colors = Theme.of(context).colorScheme;
    final enabled =
        !busy.value && !account.loading && repository.value?.available == true;
    Future<void> perform(Future<void> Function() action, String success) async {
      if (busy.value) return;
      busy.value = true;
      try {
        await action();
        if (context.mounted) showMessage(context, success);
      } catch (failure) {
        if (context.mounted) {
          showMessage(
            context,
            failure is AccountFailure
                ? failure.message
                : '通信できませんでした。設定を確認して再度お試しください。',
          );
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> open(AccountFormMode mode) async {
      if (busy.value) return;
      busy.value = true;
      try {
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => AccountFormScreen(mode: mode)),
        );
        if (saved == true && context.mounted) {
          showMessage(
            context,
            mode == AccountFormMode.login ? 'ログインしました。' : 'プロフィールを保存しました。',
          );
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> logout() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ログアウトしますか？'),
          content: const Text('旅程・旅行の基本設定はこの端末に残ります。投稿はクラウドに保存されています。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ログアウト'),
            ),
          ],
        ),
      );
      if (confirmed == true && context.mounted) {
        await perform(
          ref.read(accountActionsProvider).signOut,
          'ゲストさんとして利用できます。',
        );
      }
    }

    return Container(
      key: const ValueKey('account-profile-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: colors.primaryContainer,
                child: Icon(
                  account.registered ? Icons.person : Icons.person_outline,
                  color: colors.primary,
                  size: 29,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      key: const ValueKey('account-display-name'),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      account.registered ? '登録済みプロフィール' : '登録なしでも使えます',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (account.registered) ...[
            Text(
              account.identity.email ?? '',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            if (account.profileLoading)
              const LinearProgressIndicator()
            else if (account.error != null) ...[
              const Text(
                'プロフィールを読み込めませんでした。Firebaseの設定と通信を確認してください。',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              TextButton(
                onPressed: () => ref.invalidate(
                  accountDetailsProvider(account.identity.uid),
                ),
                child: const Text('読み込み直す'),
              ),
            ] else if (account.details != null)
              Text(
                '${account.details!.ageGroup} · ${account.details!.prefecture} ${account.details!.municipality}',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.onSurfaceVariant,
                  height: 1.6,
                ),
              )
            else
              const Text(
                '年代やお住まいの登録を完了してください。',
                style: TextStyle(fontSize: 12),
              ),
          ],
          if (!account.loading && account.identity.uid != 'guest-loading')
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ID: ${account.identity.uid}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'ユーザーIDをコピー',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: account.identity.uid),
                    );
                    if (context.mounted) {
                      showMessage(context, 'ユーザーIDをコピーしました。');
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
          if (account.registered) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      enabled &&
                          !account.profileLoading &&
                          account.error == null
                      ? () => open(AccountFormMode.edit)
                      : null,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(
                    account.details == null ? '登録を完了する' : 'プロフィールを編集',
                  ),
                ),
                TextButton(
                  onPressed: enabled ? logout : null,
                  child: const Text('ログアウト'),
                ),
              ],
            ),
            if (!account.identity.emailVerified)
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: enabled
                        ? () => perform(
                            ref.read(accountActionsProvider).sendVerification,
                            '確認メールを送信しました。',
                          )
                        : null,
                    child: const Text('確認メールを送信'),
                  ),
                  TextButton(
                    onPressed: enabled
                        ? () => perform(
                            ref.read(accountActionsProvider).reloadIdentity,
                            '確認状態を更新しました。',
                          )
                        : null,
                    child: const Text('確認状態を更新'),
                  ),
                ],
              )
            else
              const Text('メール確認済み', style: TextStyle(fontSize: 11)),
            TextButton(
              onPressed: enabled && account.identity.email != null
                  ? () => perform(
                      () => ref
                          .read(accountActionsProvider)
                          .resetPassword(account.identity.email!),
                      'パスワード再設定メールを送信しました。',
                    )
                  : null,
              child: const Text('パスワードを再設定'),
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton(
                  onPressed: enabled
                      ? () => open(AccountFormMode.register)
                      : null,
                  child: const Text('登録する'),
                ),
                OutlinedButton(
                  onPressed: enabled ? () => open(AccountFormMode.login) : null,
                  child: const Text('ログイン'),
                ),
              ],
            ),
            if (account.loading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
          if (repository.value?.available == false)
            Text(
              repository.value!.unavailableMessage ?? 'アカウント機能の設定を確認してください。',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          if (repository.value?.available == false)
            TextButton(
              onPressed: () => ref.invalidate(firebaseRuntimeProvider),
              child: const Text('アカウント機能に再接続'),
            ),
          if (!account.registered && account.error != null && !account.loading)
            TextButton(
              onPressed: () {
                ref.invalidate(guestIdentityProvider);
                ref.invalidate(accountIdentityProvider);
              },
              child: const Text('アカウントを読み込み直す'),
            ),
        ],
      ),
    );
  }
}
