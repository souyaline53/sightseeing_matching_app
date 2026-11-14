import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../state/app_tab.dart';
import '../state/trip_library_state.dart';
import '../state/itinerary_navigation.dart';
import '../state/settings_state.dart';
import '../state/discovery_state.dart';

void beginInterestSearch(WidgetRef ref) {
  final defaults = ref.read(settingsProvider).requireValue.profile.defaults();
  ref.read(searchDraftProvider.notifier).replace(defaults);
  ref.read(discoveryProvider.notifier).beginSearch();
  ref.read(appTabProvider.notifier).select(AppTab.home);
}

void openItinerarySetup(BuildContext context, WidgetRef ref) {
  ref.read(itineraryEditorProvider.notifier).close();
  ref.read(appTabProvider.notifier).select(AppTab.itinerary);
  Navigator.of(context).popUntil((route) => route.isFirst);
}

void openTripBooklet(BuildContext context, WidgetRef ref, String tripId) {
  ref.read(tripLibraryProvider.notifier).select(tripId);
  ref.read(appTabProvider.notifier).select(AppTab.bookmark);
  Navigator.of(context).popUntil((route) => route.isFirst);
}
