import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../state/itinerary_navigation.dart';
import 'itinerary_editor.dart';
import 'itinerary_setup_screen.dart';
export 'plan_screen.dart';

class ItineraryHome extends ConsumerWidget {
  final bool active;
  const ItineraryHome({super.key, this.active = true});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = ref.read(itineraryEditorProvider.notifier);
    final editing = ref.watch(itineraryEditorProvider);
    return PopScope(
      canPop: !editing || !active,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && editing && active) navigation.close();
      },
      child: editing
          ? ItineraryEditor(onBack: navigation.close)
          : const ItinerarySetupScreen(),
    );
  }
}
