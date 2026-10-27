import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/settings_state.dart';
import '../../state/discovery_state.dart';
import '../../state/conditions_step_state.dart';
import '../../service/search_execution_service.dart';
import '../../widgets/settings_actions.dart';
import 'conditions_step_pages.dart';

class SearchConditionsScreen extends HookConsumerWidget {
  const SearchConditionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(() {
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
    return ScaffoldMessenger(
      child: Builder(
        builder: (pageContext) {
          Future<void> execute(bool skip) async {
            if (busy.value) return;
            busy.value = true;
            try {
              await ref
                  .read(searchExecutionProvider)
                  .execute(skipDetails: skip);
            } catch (_) {
              if (pageContext.mounted) {
                showMessage(pageContext, '検索条件を保存できませんでした。入力を確認してもう一度お試しください。');
              }
            } finally {
              if (context.mounted) busy.value = false;
            }
          }

          return Scaffold(
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              leading: BackButton(
                onPressed: () {
                  if (busy.value) return;
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
                TransportStepPage(),
                DetailsStepPage(),
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (step == 0)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          if (ref.read(conditionsStepProvider) != 0) return;
                          if (ref
                              .read(searchDraftProvider)
                              .origin
                              .trim()
                              .isEmpty) {
                            showMessage(pageContext, '出発地を選択してください。');
                            return;
                          }
                          FocusScope.of(context).unfocus();
                          ref.read(conditionsStepProvider.notifier).nextFrom(0);
                        },
                        child: const Text('この出発地にする'),
                      ),
                    ),
                  if (step == 1)
                    const Text(
                      '移動手段をタップして、次へ進みます。',
                      style: TextStyle(fontSize: 12),
                    ),
                  if (step == 2) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: busy.value ? null : () => execute(false),
                        child: const Text('この条件で探す'),
                      ),
                    ),
                    TextButton(
                      onPressed: busy.value ? null : () => execute(true),
                      child: const Text('詳細設定をスキップ'),
                    ),
                    TextButton.icon(
                      onPressed: busy.value
                          ? null
                          : () async {
                              if (busy.value) return;
                              final filters = ref.read(searchDraftProvider);
                              final error = filters.validateFilters();
                              if (error != null) {
                                showMessage(pageContext, error);
                                return;
                              }
                              busy.value = true;
                              try {
                                final name = await askPresetName(pageContext);
                                if (name == null || !context.mounted) return;
                                await ref
                                    .read(settingsProvider.notifier)
                                    .savePreset(filters, name);
                                if (pageContext.mounted) {
                                  showMessage(pageContext, '検索条件を保存しました。');
                                }
                              } catch (_) {
                                if (pageContext.mounted) {
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
