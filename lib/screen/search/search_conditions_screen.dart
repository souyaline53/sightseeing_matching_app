import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/settings_state.dart';
import '../../state/discovery_state.dart';
import '../../widgets/conditions_form.dart';
import '../../widgets/settings_actions.dart';

class SearchConditionsScreen extends HookConsumerWidget {
  const SearchConditionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conditions = ref.watch(searchDraftProvider);
    final busy = useState(false);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => ref.read(discoveryProvider.notifier).back(),
        ),
        title: const Text('旅行条件を設定'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 110),
        children: [
          const Text(
            '行ける条件から、冒険を。',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('予算は旅行全体の上限です。好奇心は、この先で。'),
          const SizedBox(height: 24),
          ConditionsForm(
            value: conditions,
            onChanged: ref.read(searchDraftProvider.notifier).replace,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy.value
                ? null
                : () {
                    final error = conditions.validate();
                    if (error != null) {
                      showMessage(context, error);
                      return;
                    }
                    ref.read(discoveryProvider.notifier).startQuestions();
                  },
            child: const Text('次へ'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy.value
                ? null
                : () async {
                    final error = conditions.validate();
                    if (error != null) {
                      showMessage(context, error);
                      return;
                    }
                    final name = await askPresetName(context);
                    if (name == null || !context.mounted) return;
                    busy.value = true;
                    try {
                      await ref
                          .read(settingsProvider.notifier)
                          .savePreset(conditions, name);
                      if (context.mounted) showMessage(context, '検索条件を保存しました。');
                    } catch (_) {
                      if (context.mounted) {
                        showMessage(context, '保存できませんでした。もう一度お試しください。');
                      }
                    } finally {
                      if (context.mounted) busy.value = false;
                    }
                  },
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('この条件を保存'),
          ),
        ],
      ),
    );
  }
}
