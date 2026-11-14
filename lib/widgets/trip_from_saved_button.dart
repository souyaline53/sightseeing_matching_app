import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../state/app_tab.dart';
import '../state/itinerary_navigation.dart';
import '../state/trip_library_state.dart';

void openItinerarySetup(BuildContext context, WidgetRef ref) {
  ref.read(itineraryEditorProvider.notifier).close();
  ref.read(appTabProvider.notifier).select(AppTab.itinerary);
  Navigator.of(context).popUntil((route) => route.isFirst);
}

class TripFromSavedButton extends ConsumerWidget {
  const TripFromSavedButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    child: FilledButton.icon(
      onPressed: ref.watch(savedExperiencesProvider).isEmpty
          ? null
          : () => openItinerarySetup(context, ref),
      icon: const Icon(Icons.bookmark_outline),
      label: const Text('保存した観光地で旅を作る'),
    ),
  );
}
