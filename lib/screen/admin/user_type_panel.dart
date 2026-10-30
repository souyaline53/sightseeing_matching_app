import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../service/cloud/municipality_admin_service.dart';
import '../../widgets/user_type_badge.dart';
import '../../model/chat.dart';

class UserTypePanel extends HookConsumerWidget {
  const UserTypePanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = useTextEditingController();
    final busy = useState(false);
    final result = useState<ChatAccount?>(null);
    final error = useState<String?>(null);
    final formKey = useMemoized(GlobalKey<FormState>.new);
    Future<void> submit() async {
      if (busy.value || !formKey.currentState!.validate()) return;
      FocusScope.of(context).unfocus();
      busy.value = true;
      error.value = null;
      result.value = null;
      try {
        final account = await ref
            .read(municipalityAdminServiceProvider)
            .promote(email.text);
        if (context.mounted) result.value = account;
      } catch (failure) {
        if (context.mounted) {
          error.value = failure is StateError
              ? failure.message
              : '変更できませんでした。通信と権限を確認してください。';
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.account_balance_outlined, size: 38),
            const SizedBox(height: 18),
            const Text(
              '自治体ユーザに変更',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              '対象者がTABISAKIに登録したメールアドレスを入力してください。プロフィール登録が完了しているアカウントが対象です。',
              style: TextStyle(fontSize: 13, height: 1.7),
            ),
            const SizedBox(height: 24),
            TextFormField(
              key: const ValueKey('municipality-email'),
              controller: email,
              enabled: !busy.value,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '対象者のメールアドレス',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: (value) =>
                  RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch(value?.trim() ?? '')
                  ? null
                  : 'メールアドレスを入力してください。',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy.value ? null : submit,
              icon: busy.value
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label: const Text('自治体ユーザに変更する'),
            ),
            if (error.value != null)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Text(
                  error.value!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (result.value != null)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('「${result.value!.displayName}」を自治体ユーザに変更しました。'),
                    const SizedBox(height: 8),
                    UserTypeBadge(result.value!.userType),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
