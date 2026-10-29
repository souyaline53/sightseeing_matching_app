import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/trip_library_state.dart';
import '../../state/trip_state.dart';
import '../../widgets/travel_photo.dart';

String tripDateLabel(TripState trip) => trip.travelDate == null
    ? '日程未定'
    : '${trip.travelDate!.year}年${trip.travelDate!.month}月${trip.travelDate!.day}日';

class TripsDrawer extends HookConsumerWidget {
  final VoidCallback onNewTrip;
  const TripsDrawer({super.key, required this.onNewTrip});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(tripLibraryProvider).requireValue;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Drawer(
        width: (constraints.maxWidth * .9).clamp(0.0, 360.0),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 12, 12),
                child: Row(
                  children: [
                    Icon(Icons.auto_stories_outlined, color: colors.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'わたしの旅',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '閉じる',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onNewTrip();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('新しい旅を追加'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '保存した旅  ${library.plans.length}件',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: library.plans.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            '保存した旅はまだありません。',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                        itemCount: library.plans.length,
                        itemBuilder: (context, index) {
                          final trip = library.plans[index];
                          final selected = library.activeId == trip.id;
                          final photo =
                              trip.stops.firstOrNull ?? trip.saved.firstOrNull;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: selected
                                  ? colors.primaryContainer
                                  : colors.surface,
                              borderRadius: BorderRadius.circular(18),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 12,
                                  right: 0,
                                  top: 8,
                                  bottom: 8,
                                ),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 44,
                                    height: 54,
                                    child: photo != null
                                        ? TravelPhoto(photo)
                                        : ColoredBox(
                                            color: colors.primary.withValues(
                                              alpha: .08,
                                            ),
                                            child: Icon(
                                              Icons.landscape_outlined,
                                              color: colors.primary,
                                            ),
                                          ),
                                  ),
                                ),
                                title: Text(
                                  trip.displayTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  tripDateLabel(trip),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                selected: selected,
                                onTap: () {
                                  ref
                                      .read(tripProvider.notifier)
                                      .openPlan(trip.id);
                                  Navigator.of(context).pop();
                                },
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selected)
                                      Icon(
                                        Icons.check_circle,
                                        size: 18,
                                        color: colors.primary,
                                      ),
                                    TripActionsMenu(
                                      trip: trip,
                                      onOpen: () => Navigator.of(context).pop(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TripAction { open, rename, duplicate, delete }

class TripActionsMenu extends HookConsumerWidget {
  final TripState trip;
  final VoidCallback? onOpen;
  const TripActionsMenu({super.key, required this.trip, this.onOpen});
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => PopupMenuButton<_TripAction>(
    tooltip: '旅行計画の操作',
    onSelected: (action) async {
      final controller = ref.read(tripLibraryProvider.notifier);
      switch (action) {
        case _TripAction.open:
          ref.read(tripProvider.notifier).openPlan(trip.id);
          onOpen?.call();
        case _TripAction.rename:
          final title = await showDialog<String>(
            context: context,
            builder: (_) => _RenameTripDialog(title: trip.displayTitle),
          );
          if (title != null && context.mounted) {
            controller.rename(trip.id, title);
          }
        case _TripAction.duplicate:
          controller.duplicate(trip.id);
        case _TripAction.delete:
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('この旅程を削除しますか？'),
              content: Text('「${trip.displayTitle}」を削除します。\nこの操作は取り消せません。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('削除する'),
                ),
              ],
            ),
          );
          if (confirmed == true && context.mounted) controller.delete(trip.id);
      }
    },
    itemBuilder: (context) => [
      const PopupMenuItem(value: _TripAction.open, child: Text('旅程を開く')),
      const PopupMenuItem(value: _TripAction.rename, child: Text('名前を変更する')),
      const PopupMenuItem(value: _TripAction.duplicate, child: Text('旅程を複製する')),
      PopupMenuItem(
        value: _TripAction.delete,
        child: Text(
          '旅程を削除する',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    ],
  );
}

class _RenameTripDialog extends HookConsumerWidget {
  final String title;
  const _RenameTripDialog({required this.title});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = useTextEditingController(text: title);
    final error = useState<String?>(null);
    void save() {
      final value = text.text.trim();
      if (value.isEmpty) {
        error.value = '旅行タイトルを入力してください。';
        return;
      }
      Navigator.of(context).pop(value);
    }

    return AlertDialog(
      title: const Text('旅の名前を変更'),
      content: TextField(
        controller: text,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => save(),
        onChanged: (_) => error.value = null,
        decoration: InputDecoration(
          labelText: '旅行タイトル',
          errorText: error.value,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(onPressed: save, child: const Text('保存する')),
      ],
    );
  }
}
