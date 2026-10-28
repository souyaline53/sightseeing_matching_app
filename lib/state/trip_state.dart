import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/experience.dart';
import '../model/search_settings.dart';
import '../model/trip_plan.dart';
import 'trip_library_state.dart';
export '../model/trip_plan.dart' show TripState;

final tripProvider = NotifierProvider<TripNotifier, TripState>(
  TripNotifier.new,
);

class TripNotifier extends Notifier<TripState> {
  @override
  TripState build() =>
      ref.watch(
        tripLibraryProvider.select((value) => value.value?.activeTrip),
      ) ??
      TripState(id: 'loading');
  void _commit(TripState next) {
    if (next.title.isEmpty && next.stops.isNotEmpty) {
      next = next.copyWith(title: '${next.stops.first.area}の小さな旅');
    }
    ref.read(tripLibraryProvider.notifier).upsert(next);
  }

  void applyConditions(SearchConditions conditions) =>
      _commit(state.copyWith(conditions: conditions));
  void applySearchFilters(SearchConditions filters) {
    final next = state.stops.isEmpty && state.saved.isEmpty
        ? state.copyWith(conditions: filters, clearDate: true)
        : TripState(conditions: filters);
    _commit(next);
  }

  void save(Experience e) {
    if (!state.contains(e)) {
      _commit(
        state.copyWith(
          saved: [...state.saved, e],
          stops: state.stops.contains(e) ? state.stops : [...state.stops, e],
        ),
      );
    }
  }

  void toggle(Experience e) {
    if (state.contains(e)) {
      _commit(
        state.copyWith(
          saved: state.saved.where((x) => x.id != e.id).toList(),
          stops: state.stops.where((x) => x.id != e.id).toList(),
        ),
      );
    } else {
      save(e);
    }
  }

  void addStop(Experience e) {
    if (!state.stops.contains(e)) {
      _commit(state.copyWith(stops: [...state.stops, e]));
    }
  }

  void removeStop(Experience e) => _commit(
    state.copyWith(stops: state.stops.where((x) => x.id != e.id).toList()),
  );
  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final stops = [...state.stops];
    stops.insert(newIndex, stops.removeAt(oldIndex));
    _commit(state.copyWith(stops: stops));
  }

  void setDate(DateTime date) => _commit(
    state.copyWith(
      travelDate: DateTime(date.year, date.month, date.day),
      conditions: state.conditions.copyWith(
        dateChoice: DateChoice.fixed,
        fixedDate: date,
      ),
    ),
  );
  void setOrigin(String origin) =>
      applyConditions(state.conditions.copyWith(origin: origin));
  void setTravelMode(TravelMode mode) =>
      applyConditions(state.conditions.copyWith(transport: mode));
}
