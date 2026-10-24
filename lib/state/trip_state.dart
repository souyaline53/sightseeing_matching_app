import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/experience.dart';

class TripState {
  final List<Experience> saved, stops;
  final DateTime date;
  final String origin;
  final bool publicTransport;
  TripState({
    List<Experience> saved = const [],
    List<Experience> stops = const [],
    DateTime? date,
    this.origin = '札幌駅',
    this.publicTransport = true,
  }) : saved = List.unmodifiable(saved),
       stops = List.unmodifiable(stops),
       date = date ?? DateTime.now().add(const Duration(days: 1));
  bool contains(Experience e) => saved.any((x) => x.id == e.id);
  TripState copyWith({
    List<Experience>? saved,
    List<Experience>? stops,
    DateTime? date,
    String? origin,
    bool? publicTransport,
  }) => TripState(
    saved: saved ?? this.saved,
    stops: stops ?? this.stops,
    date: date ?? this.date,
    origin: origin ?? this.origin,
    publicTransport: publicTransport ?? this.publicTransport,
  );
}

final tripProvider = NotifierProvider<TripNotifier, TripState>(
  TripNotifier.new,
);

class TripNotifier extends Notifier<TripState> {
  @override
  TripState build() => TripState();
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

  void setDate(DateTime date) => state = state.copyWith(date: date);
  void setOrigin(String origin) => state = state.copyWith(origin: origin);
  void setTransport(bool publicTransport) =>
      state = state.copyWith(publicTransport: publicTransport);
}
