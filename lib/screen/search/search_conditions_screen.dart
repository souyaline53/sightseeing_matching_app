import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/settings_state.dart';
import '../../state/discovery_state.dart';
import '../../state/conditions_step_state.dart';
import '../../widgets/settings_actions.dart';
import 'conditions_step_pages.dart';

class SearchConditionsScreen extends HookConsumerWidget {
  const SearchConditionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(() {
      // A notification from the previous tab must not cover this fixed footer.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
        }
      });
      return null;
    }, const []);
    final step = ref.watch(conditionsStepProvider);
    final busy = useState(false);
    final pages = usePageController(initialPage: step);
    ref.listen(conditionsStepProvider, (_, next) {
      if (pages.hasClients) {
        pages.animateToPage(
          next,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeInOut,
        );
      }
    });
    String? validate() {
      final current = ref.read(searchDraftProvider);
      if (current.origin.trim().isEmpty) return '出発地を入力してください。';
      if (current.maxMinutes < 30 || current.maxMinutes > 240) {
        return '片道移動時間を30〜240分で選び直してください。';
      }
      if (step > 0) return current.validate();
      return null;
    }

    return ScaffoldMessenger(
      child: Builder(
        builder: (pageContext) => Scaffold(
          // The containing BasePage Scaffold already resizes for the keyboard.
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            leading: BackButton(
              onPressed: busy.value
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      ref.read(discoveryProvider.notifier).back();
                    },
            ),
            title: const Text('旅行条件を設定'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(42),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STEP ${step + 1}/3',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (step + 1) / 3,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: PageView(
            controller: pages,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              DepartureStepPage(),
              ScheduleStepPage(),
              CompanyStepPage(),
            ],
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy.value
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            final error = validate();
                            if (error != null) {
                              showMessage(pageContext, error);
                              return;
                            }
                            if (step < 2) {
                              ref.read(conditionsStepProvider.notifier).next();
                            } else {
                              ref
                                  .read(discoveryProvider.notifier)
                                  .startQuestions();
                            }
                          },
                    child: Text(step == 2 ? '次へ：好奇心を探す' : '次へ'),
                  ),
                ),
                if (step == 2)
                  TextButton.icon(
                    onPressed: busy.value
                        ? null
                        : () async {
                            final error = validate();
                            if (error != null) {
                              showMessage(pageContext, error);
                              return;
                            }
                            final conditions = ref.read(searchDraftProvider);
                            final name = await askPresetName(pageContext);
                            if (name == null || !context.mounted) return;
                            busy.value = true;
                            try {
                              await ref
                                  .read(settingsProvider.notifier)
                                  .savePreset(conditions, name);
                              if (context.mounted) {
                                showMessage(pageContext, '検索条件を保存しました。');
                              }
                            } catch (_) {
                              if (context.mounted) {
                                showMessage(
                                  pageContext,
                                  '保存できませんでした。もう一度お試しください。',
                                );
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
          ),
        ),
      ),
    );
  }
}
