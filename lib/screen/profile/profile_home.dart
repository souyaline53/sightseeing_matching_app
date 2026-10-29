import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/search_settings.dart';
import '../../state/app_tab.dart';
import '../../state/discovery_state.dart';
import '../../state/settings_state.dart';
import 'widgets/conditions_form.dart';
import 'profile_setting_screen.dart';
import '../../widgets/settings_actions.dart';

class ProfileHome extends HookConsumerWidget {
  const ProfileHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).requireValue;
    final busy = useState(false);
    Future<void> perform(Future<void> Function() action) async {
      busy.value = true;
      try {
        await action();
        if (context.mounted) showMessage(context, '保存しました。');
      } catch (_) {
        if (context.mounted) {
          showMessage(context, '保存できませんでした。入力を確認して再度お試しください。');
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 110),
        children: [
          const Text(
            '基本設定',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          for (final setting in ProfileSetting.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: ProfileSettingTile(
                  setting: setting,
                  value: setting.summary(settings.profile),
                  onTap: busy.value
                      ? null
                      : () async {
                          final saved = await Navigator.of(context).push<bool>(
                            PageRouteBuilder<bool>(
                              pageBuilder: (_, animation, secondaryAnimation) =>
                                  ProfileSettingScreen(setting: setting),
                              transitionsBuilder:
                                  (_, animation, secondaryAnimation, child) =>
                                      SlideTransition(
                                        position:
                                            Tween<Offset>(
                                              begin: const Offset(1, 0),
                                              end: Offset.zero,
                                            ).animate(
                                              CurvedAnimation(
                                                parent: animation,
                                                curve: Curves.easeInOutCubic,
                                              ),
                                            ),
                                        child: child,
                                      ),
                            ),
                          );
                          if (saved == true && context.mounted) {
                            showMessage(context, '基本設定を保存しました。');
                          }
                        },
                ),
              ),
            ),
          const SizedBox(height: 32),
          const Text(
            '保存した検索条件',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          if (settings.presets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('旅行条件の「条件を保存して検索」から追加できます。'),
            ),
          for (final preset in settings.presets)
            Card(
              key: ValueKey(preset.id),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(preset.conditions.summary),
                    Text(
                      '${['明日', '週末', '日付指定'][preset.conditions.dateChoice.index]} · 徒歩${preset.conditions.walking.label} · ${preset.conditions.company.label}',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: busy.value
                              ? null
                              : () {
                                  ref
                                      .read(searchDraftProvider.notifier)
                                      .replace(preset.conditions);
                                  ref
                                      .read(discoveryProvider.notifier)
                                      .startConditions();
                                  ref
                                      .read(appTabProvider.notifier)
                                      .select(AppTab.recommendation);
                                },
                          child: const Text('読み込み'),
                        ),
                        TextButton(
                          onPressed: busy.value
                              ? null
                              : () async {
                                  final name = await askPresetName(
                                    context,
                                    initial: preset.name,
                                  );
                                  if (name != null && context.mounted) {
                                    await perform(
                                      () => ref
                                          .read(settingsProvider.notifier)
                                          .savePreset(
                                            preset.conditions,
                                            name,
                                            id: preset.id,
                                          ),
                                    );
                                  }
                                },
                          child: const Text('名前の変更'),
                        ),
                        TextButton(
                          onPressed: busy.value
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        PresetEditor(preset: preset),
                                  ),
                                ),
                          child: const Text('内容の編集'),
                        ),
                        TextButton(
                          onPressed: busy.value
                              ? null
                              : () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('検索条件を削除しますか？'),
                                      content: Text('「${preset.name}」を削除します。'),
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
                                  if (confirmed == true && context.mounted) {
                                    await perform(
                                      () => ref
                                          .read(settingsProvider.notifier)
                                          .deletePreset(preset.id),
                                    );
                                  }
                                },
                          child: const Text('削除'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PresetEditor extends HookConsumerWidget {
  final SearchPreset preset;
  const PresetEditor({super.key, required this.preset});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = useState(preset.conditions);
    final busy = useState(false);
    return Scaffold(
      appBar: AppBar(title: Text('編集：${preset.name}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 110),
        children: [
          ConditionsForm(value: draft.value, onChanged: (v) => draft.value = v),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy.value
                ? null
                : () async {
                    final error = draft.value.validate();
                    if (error != null) {
                      showMessage(context, error);
                      return;
                    }
                    busy.value = true;
                    try {
                      await ref
                          .read(settingsProvider.notifier)
                          .savePreset(draft.value, preset.name, id: preset.id);
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      if (context.mounted) {
                        showMessage(context, '保存できませんでした。もう一度お試しください。');
                      }
                    } finally {
                      if (context.mounted) busy.value = false;
                    }
                  },
            child: const Text('上書き保存'),
          ),
        ],
      ),
    );
  }
}
