import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/search_settings.dart';
import '../../state/settings_state.dart';
import '../../widgets/settings_actions.dart';

enum ProfileSetting {
  origin,
  transport,
  budget,
  walking;

  String get title => switch (this) {
    origin => '出発地',
    transport => '移動手段',
    budget => '旅行予算',
    walking => '徒歩負担',
  };

  IconData get icon => switch (this) {
    origin => Icons.trip_origin,
    transport => Icons.directions_train_outlined,
    budget => Icons.account_balance_wallet_outlined,
    walking => Icons.directions_walk,
  };

  String get description => switch (this) {
    origin => 'いつも旅を始める駅や地域を教えてください。',
    transport => '普段の旅で使いたい移動手段を選んでください。',
    budget => '交通費・食事・体験・宿泊を含む、旅行全体の目安です。',
    walking => '心地よく旅を楽しめる、歩く量を選んでください。',
  };

  String summary(UserProfile profile) => switch (this) {
    origin => profile.origin.isEmpty ? '未設定' : profile.origin,
    transport => profile.transport.label,
    budget => '${_yen(profile.budget)}円まで',
    walking => profile.walking.label,
  };
}

String _yen(int amount) => amount.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]},',
);

class ProfileSettingTile extends HookConsumerWidget {
  final ProfileSetting setting;
  final String value;
  final VoidCallback? onTap;
  const ProfileSettingTile({
    super.key,
    required this.setting,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(setting.icon, color: colors.primary, size: 23),
      ),
      title: Text(
        setting.title,
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          value,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: colors.primary, size: 22),
      onTap: onTap,
    );
  }
}

/// Each route edits one field; other profile defaults and presets stay intact.
class ProfileSettingScreen extends HookConsumerWidget {
  final ProfileSetting setting;
  const ProfileSettingScreen({super.key, required this.setting});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = ref.read(settingsProvider).requireValue.profile;
    final draft = useState(initial.defaults());
    final origin = useTextEditingController(text: initial.origin);
    final busy = useState(false);
    final colors = Theme.of(context).colorScheme;

    Widget choices<T>(
      List<T> values,
      T selected,
      String Function(T) label,
      ValueChanged<T> select,
    ) => Column(
      children: [
        for (final value in values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: selected == value
                  ? colors.primaryContainer
                  : colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: selected == value
                      ? colors.primary
                      : colors.outlineVariant,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                title: Text(label(value)),
                trailing: Icon(
                  selected == value
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: selected == value ? colors.primary : colors.outline,
                ),
                onTap: busy.value ? null : () => select(value),
              ),
            ),
          ),
      ],
    );

    Future<void> save() async {
      if (busy.value) return;
      if (setting == ProfileSetting.origin && origin.text.trim().isEmpty) {
        showMessage(context, '普段の出発地を入力してください。');
        return;
      }
      busy.value = true;
      FocusScope.of(context).unfocus();
      try {
        final current = ref.read(settingsProvider).requireValue.profile;
        await ref
            .read(settingsProvider.notifier)
            .saveProfile(
              UserProfile(
                origin: setting == ProfileSetting.origin
                    ? origin.text.trim()
                    : current.origin,
                transport: setting == ProfileSetting.transport
                    ? draft.value.transport
                    : current.transport,
                budget: setting == ProfileSetting.budget
                    ? draft.value.budget
                    : current.budget,
                walking: setting == ProfileSetting.walking
                    ? draft.value.walking
                    : current.walking,
              ),
            );
        if (context.mounted) Navigator.of(context).pop(true);
      } catch (_) {
        if (context.mounted) {
          showMessage(context, '保存できませんでした。もう一度お試しください。');
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return PopScope(
      canPop: !busy.value,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Scaffold(
            appBar: AppBar(
              title: Text(setting.title),
              leading: BackButton(
                onPressed: busy.value
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: colors.primary.withValues(alpha: .08),
                    child: Icon(setting.icon, color: colors.primary, size: 28),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'いつもの${setting.title}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  setting.description,
                  style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
                ),
                const SizedBox(height: 28),
                switch (setting) {
                  ProfileSetting.origin => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: origin,
                        enabled: !busy.value,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => save(),
                        decoration: const InputDecoration(
                          labelText: '駅名・地域名',
                          prefixIcon: Icon(Icons.place_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final name in ['札幌駅', '新千歳空港', '小樽駅', '旭川駅'])
                            ActionChip(
                              label: Text(name),
                              onPressed: busy.value
                                  ? null
                                  : () => origin.text = name,
                            ),
                        ],
                      ),
                    ],
                  ),
                  ProfileSetting.transport => choices(
                    TravelMode.values,
                    draft.value.transport,
                    (mode) => mode.label,
                    (mode) =>
                        draft.value = draft.value.copyWith(transport: mode),
                  ),
                  ProfileSetting.walking => choices(
                    Walking.values,
                    draft.value.walking,
                    (walking) => walking.label,
                    (walking) =>
                        draft.value = draft.value.copyWith(walking: walking),
                  ),
                  ProfileSetting.budget => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_yen(draft.value.budget)}円',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Slider(
                        value: draft.value.budget.toDouble(),
                        min: 1000,
                        max: 100000,
                        divisions: 99,
                        label: '${_yen(draft.value.budget)}円',
                        onChanged: busy.value
                            ? null
                            : (value) => draft.value = draft.value.copyWith(
                                budget: value.round(),
                              ),
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [Text('1,000円'), Text('100,000円')],
                      ),
                    ],
                  ),
                },
                const SizedBox(height: 24),
                Text(
                  '新しい旅の検索時に、初期設定として使われます。',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: busy.value ? null : save,
                    child: Text(busy.value ? '保存中…' : '保存する'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
