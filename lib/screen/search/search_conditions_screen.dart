import '../../data/departure_places.dart';
import '../../state/search_selection_state.dart';
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
    final companyChosen = ref
        .watch(searchSelectionProvider)
        .contains(SearchSelection.company);
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
          Future<void> execute({bool save = false}) async {
            if (busy.value) return;
            final filters = ref.read(searchDraftProvider);
            final error = filters.validateFilters();
            if (error != null) {
              showMessage(pageContext, error);
              return;
            }
            busy.value = true;
            try {
              String? name;
              if (save) {
                name = await askPresetName(pageContext);
                if (name == null || !context.mounted) return;
              }
              await ref.read(searchExecutionProvider).execute(presetName: name);
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
                        'Q${step + 4} / 7',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: (step + 4) / 7,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            body: AbsorbPointer(
              absorbing: busy.value,
              child: PageView(
                controller: pages,
                physics: const NeverScrollableScrollPhysics(),
                children: const [
                  DepartureStepPage(),
                  TripLengthStepPage(),
                  DepartureDateStepPage(),
                  CompanionStepPage(),
                ],
              ),
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
                          if (!isDepartureSelectable(
                                ref.read(searchDraftProvider).origin,
                              ) ||
                              departureNamed(
                                    ref.read(searchDraftProvider).origin,
                                    ref.read(departurePlacesProvider).value ??
                                        [],
                                  ) ==
                                  null) {
                            showMessage(pageContext, '出発地を選択してください。');
                            return;
                          }
                          ref
                              .read(searchSelectionProvider.notifier)
                              .choose(SearchSelection.origin);
                          FocusScope.of(context).unfocus();
                          ref.read(conditionsStepProvider.notifier).nextFrom(0);
                        },
                        child: const Text('この出発地にする'),
                      ),
                    ),
                  if (step == 3) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: busy.value || !companyChosen
                            ? null
                            : () => execute(),
                        icon: const Icon(Icons.search),
                        label: const Text('この条件で探す'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: busy.value || !companyChosen
                            ? null
                            : () => execute(save: true),
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('条件を保存して検索'),
                      ),
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
