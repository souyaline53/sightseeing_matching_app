import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../data/japan_regions.dart';
import '../../../model/account_profile.dart';
import '../../../state/account_state.dart';
import '../../../widgets/settings_actions.dart';

enum AccountFormMode { register, login, edit }

class AccountFormScreen extends HookConsumerWidget {
  final AccountFormMode mode;
  const AccountFormScreen({super.key, required this.mode});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider);
    final initial = useMemoized(() => account.details, const []);
    final email = useTextEditingController(
      text: account.registered ? account.identity.email : '',
    );
    final password = useTextEditingController();
    final nickname = useTextEditingController(
      text:
          initial?.nickname ??
          (account.registered && account.identity.displayName != 'プロフィール未登録'
              ? account.identity.displayName
              : ''),
    );
    final city = useTextEditingController(text: initial?.municipality ?? '');
    final age = useState<String?>(initial?.ageGroup);
    final region = useState<String?>(
      initial == null ? null : regionForPrefecture(initial.prefecture),
    );
    final prefecture = useState<String?>(initial?.prefecture);
    final hidden = useState(true), busy = useState(false);
    final form = useMemoized(() => GlobalKey<FormState>());
    final error = useState<String?>(null);
    final edit = mode == AccountFormMode.edit,
        login = mode == AccountFormMode.login;
    final title = edit
        ? 'プロフィール設定'
        : login
        ? 'ログイン'
        : 'アカウント登録';
    Future<void> submit() async {
      if (busy.value || !form.currentState!.validate()) return;
      busy.value = true;
      error.value = null;
      FocusScope.of(context).unfocus();
      try {
        final actions = ref.read(accountActionsProvider);
        if (login) {
          await actions.signIn(email.text.trim(), password.text);
        } else {
          final details = AccountDetails(
            nickname: nickname.text.trim(),
            ageGroup: age.value ?? '',
            prefecture: prefecture.value ?? '',
            municipality: city.text.trim(),
          );
          if (edit) {
            await actions.saveProfile(details);
          } else {
            await actions.register(
              email: email.text.trim(),
              password: password.text,
              details: details,
            );
          }
        }
        if (context.mounted) Navigator.pop(context, true);
      } catch (failure) {
        if (context.mounted) {
          error.value = failure is AccountFailure
              ? failure.message
              : '保存できませんでした。通信とFirebaseの設定を確認して、もう一度お試しください。';
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> resetPassword() async {
      if (email.text.trim().isEmpty) {
        error.value = '再設定メールを送るメールアドレスを入力してください。';
        return;
      }
      busy.value = true;
      try {
        await ref.read(accountActionsProvider).resetPassword(email.text.trim());
        if (context.mounted) {
          showMessage(context, '再設定メールを送信しました。受信メールを確認してください。');
        }
      } catch (failure) {
        if (context.mounted) {
          error.value = failure is AccountFailure
              ? failure.message
              : '再設定メールを送信できませんでした。';
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return PopScope(
      canPop: !busy.value,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Form(
          key: form,
          child: ListView(
            key: const ValueKey('account-form'),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              Text(
                edit
                    ? 'あなたの旅のプロフィール'
                    : login
                    ? 'おかえりなさい。旅の続きを。'
                    : 'あなただけの旅のプロフィールを。',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '登録しなくても、ゲストさんとして利用できます。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextFormField(
                key: const ValueKey('account-email'),
                controller: email,
                enabled: !busy.value && !edit,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'メールアドレス',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: (value) =>
                    edit ||
                        RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(value?.trim() ?? '')
                    ? null
                    : 'メールアドレスを入力してください。',
              ),
              if (!edit) ...[
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('account-password'),
                  controller: password,
                  enabled: !busy.value,
                  obscureText: hidden.value,
                  enableSuggestions: false,
                  autocorrect: false,
                  autofillHints: [
                    login ? AutofillHints.password : AutofillHints.newPassword,
                  ],
                  decoration: InputDecoration(
                    labelText: login ? 'パスワード' : 'パスワード（6文字以上）',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: hidden.value ? 'パスワードを表示' : 'パスワードを隠す',
                      onPressed: () => hidden.value = !hidden.value,
                      icon: Icon(
                        hidden.value
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => login
                      ? (value?.isNotEmpty == true ? null : 'パスワードを入力してください。')
                      : ((value?.length ?? 0) >= 6
                            ? null
                            : 'パスワードは6文字以上にしてください。'),
                ),
                if (login)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy.value ? null : resetPassword,
                      child: const Text('パスワードを忘れた方'),
                    ),
                  ),
              ],
              if (!login) ...[
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('account-nickname'),
                  controller: nickname,
                  enabled: !busy.value,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: 'ニックネーム',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => value?.trim().isNotEmpty == true
                      ? null
                      : 'ニックネームを入力してください。',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('account-age'),
                  initialValue: age.value,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '年代'),
                  items: [
                    for (final value in ageGroups)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: busy.value ? null : (value) => age.value = value,
                  validator: (value) => value == null ? '年代を選択してください。' : null,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: const ValueKey('account-region'),
                  initialValue: region.value,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'お住まいの地方'),
                  items: [
                    for (final value in japanRegions.keys)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: busy.value
                      ? null
                      : (value) {
                          if (value != region.value) {
                            region.value = value;
                            prefecture.value = null;
                          }
                        },
                  validator: (value) => value == null ? '地方を選択してください。' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('account-prefecture-${region.value}'),
                  initialValue: prefecture.value,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '都道府県'),
                  items: [
                    for (final value
                        in japanRegions[region.value] ?? <String>[])
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: busy.value || region.value == null
                      ? null
                      : (value) => prefecture.value = value,
                  validator: (value) => value == null ? '都道府県を選択してください。' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('account-city'),
                  controller: city,
                  enabled: !busy.value,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: '市町村',
                    hintText: '例：札幌市',
                  ),
                  validator: (value) =>
                      value?.trim().isNotEmpty == true ? null : '市町村を入力してください。',
                ),
              ],
              if (error.value != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    error.value!,
                    key: const ValueKey('account-form-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      height: 1.5,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey('account-submit'),
                onPressed: busy.value ? null : submit,
                child: Text(
                  busy.value
                      ? '処理中…'
                      : edit
                      ? 'プロフィールを保存'
                      : login
                      ? 'ログインする'
                      : '登録する',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
