import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../navigation/travel_navigation.dart';
import '../state/trip_library_state.dart';

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
