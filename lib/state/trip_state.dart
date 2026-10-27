import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/experience.dart';
import '../model/search_settings.dart';

class TripState {
  final List<Experience> saved, stops;
  final SearchConditions conditions;
  TripState({
    List<Experience> saved = const [],
    List<Experience> stops = const [],
    this.conditions = const SearchConditions(),
  }) : saved = List.unmodifiable(saved),
       stops = List.unmodifiable(stops);
  String get origin => conditions.origin;
  DateTime get date => conditions.resolveDate();
  bool get publicTransport => conditions.transport != TravelMode.car;
  bool contains(Experience e) => saved.any((x) => x.id == e.id);
  TripState copyWith({
    List<Experience>? saved,
    List<Experience>? stops,
    SearchConditions? conditions,
  }) => TripState(
    saved: saved ?? this.saved,
    stops: stops ?? this.stops,
    conditions: conditions ?? this.conditions,
  );
}

final tripProvider = NotifierProvider<TripNotifier, TripState>(
  TripNotifier.new,
);

class TripNotifier extends Notifier<TripState> {
  @override
  TripState build() => TripState();
  void applyConditions(SearchConditions conditions) =>
      state = state.copyWith(conditions: conditions);
  void save(Experience e) {
    if (!state.contains(e)) {
      state = state.copyWith(
        saved: [...state.saved, e],
        stops: state.stops.contains(e) ? state.stops : [...state.stops, e],
      );
    }
  }

  void toggle(Experience e) {
    if (state.contains(e)) {
      state = state.copyWith(
        saved: state.saved.where((x) => x.id != e.id).toList(),
        stops: state.stops.where((x) => x.id != e.id).toList(),
      );
    } else {
      save(e);
    }
  }

  void addStop(Experience e) {
    if (!state.stops.contains(e)) {
      state = state.copyWith(stops: [...state.stops, e]);
    }
  }

  void removeStop(Experience e) => state = state.copyWith(
    stops: state.stops.where((x) => x.id != e.id).toList(),
  );
  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final stops = [...state.stops];
    stops.insert(newIndex, stops.removeAt(oldIndex));
    state = state.copyWith(stops: stops);
  }

  void setDate(DateTime date) => applyConditions(
    state.conditions.copyWith(dateChoice: DateChoice.fixed, fixedDate: date),
  );
  void setOrigin(String origin) =>
      applyConditions(state.conditions.copyWith(origin: origin));
  void setTransport(bool publicTransport) =>
      setTravelMode(publicTransport ? TravelMode.transit : TravelMode.car);
  void setTravelMode(TravelMode mode) =>
      applyConditions(state.conditions.copyWith(transport: mode));
}
