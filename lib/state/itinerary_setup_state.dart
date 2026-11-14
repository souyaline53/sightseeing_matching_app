import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/search_settings.dart';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

class ItinerarySetup {
  final SearchConditions conditions;
  final String destination;
  final int departureMinutes;
  final Set<String> selectedIds;
  ItinerarySetup({
    SearchConditions? conditions,
    this.destination = '札幌駅',
    this.departureMinutes = 480,
    this.selectedIds = const {},
  }) : conditions =
           conditions ??
           SearchConditions(dateChoice: DateChoice.fixed, fixedDate: _today());

  ItinerarySetup copyWith({
    SearchConditions? conditions,
    String? destination,
    int? departureMinutes,
    Set<String>? selectedIds,
  }) => ItinerarySetup(
    conditions: conditions ?? this.conditions,
    destination: destination ?? this.destination,
    departureMinutes: departureMinutes ?? this.departureMinutes,
    selectedIds: selectedIds ?? this.selectedIds,
  );
}

final itinerarySetupProvider =
    NotifierProvider<ItinerarySetupNotifier, ItinerarySetup>(
      ItinerarySetupNotifier.new,
    );

class ItinerarySetupNotifier extends Notifier<ItinerarySetup> {
  @override
  ItinerarySetup build() => ItinerarySetup();
  void update(ItinerarySetup setup) => state = setup;
  void applySearch(SearchConditions conditions) => state = ItinerarySetup(
    conditions: conditions,
    selectedIds: state.selectedIds,
  );
  void toggle(String id) {
    final ids = {...state.selectedIds};
    if (!ids.remove(id)) ids.add(id);
    state = state.copyWith(selectedIds: Set.unmodifiable(ids));
  }
}
