import '../model/transport.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../model/experience.dart';
import '../model/search_settings.dart';
import '../model/trip_plan.dart';
import 'trip_library_state.dart';
import 'itinerary_navigation.dart';
export '../model/trip_plan.dart' show TripState;

final tripProvider = NotifierProvider<TripNotifier, TripState>(
  TripNotifier.new,
);

class TripNotifier extends Notifier<TripState> {
  @override
  TripState build() {
    ref.listen(tripLibraryProvider, (previous, next) {
      if (previous?.value?.activeTrip != next.value?.activeTrip) {
        state = next.value?.activeTrip ?? TripState();
      }
    });
    return ref.read(tripLibraryProvider).value?.activeTrip ?? TripState();
  }

  void _commit(TripState next) {
    if (next.title.isEmpty && next.stops.isNotEmpty) {
      next = next.copyWith(title: '${next.stops.first.area}の小さな旅');
    }
    ref.read(tripLibraryProvider.notifier).upsert(next);
  }

  void adoptAi() {
    if (!state.aiProposalValid) return;
    _commit(
      state.copyWith(
        ai: {...state.ai, 'enabled': true},
        transportSelections: [],
      ),
    );
  }

  void replaceAi(Map<String, dynamic> ai) => _commit(state.copyWith(ai: ai));
  void acceptAi(Map<String, dynamic> result, String basisBefore) {
    final metadata = Map<String, dynamic>.from(result['aiMetadata'] as Map);
    final order = (metadata['visitOrder'] as List).cast<String>();
    final byId = {for (final e in state.stops) e.id: e};
    final canApply =
        state.aiBasis == basisBefore &&
        order.length == byId.length &&
        order.toSet().length == order.length &&
        order.every(byId.containsKey);
    var next = state.copyWith(
      stops: canApply ? order.map((id) => byId[id]!).toList() : null,
      ai: {
        ...state.ai,
        'status': 'completed',
        'result': result,
        'resultRequestId': state.ai['requestId'],
        'enabled': canApply,
      },
    );
    if (canApply && state.ai['config'] is Map) {
      final config = state.ai['config'] as Map;
      final date = DateTime.parse(config['date'] as String);
      next = next.copyWith(
        travelDate: date,
        destination: (config['destination'] as Map)['id'] as String,
        departureMinutes: (config['departureSeconds'] as int) ~/ 60,
        conditions: state.conditions.copyWith(
          origin: (config['origin'] as Map)['id'] as String,
          transport: TravelMode.transit,
          length: (config['deadlineSeconds'] as int) ~/ 86400 >= 2
              ? TripLength.longer
              : (config['deadlineSeconds'] as int) ~/ 86400 == 1
              ? TripLength.overnight
              : state.conditions.length == TripLength.halfDay
              ? TripLength.halfDay
              : TripLength.day,
          dateChoice: DateChoice.fixed,
          fixedDate: date,
        ),
        stayMinutes: {
          ...state.stayMinutes,
          for (final v in config['visits'] as List)
            v['id'] as String: (v['staySeconds'] as int) ~/ 60,
        },
        transportSelections: [],
      );
    }
    next = next.copyWith(
      ai: {...next.ai, 'basis': canApply ? next.aiBasis : basisBefore},
    );
    _commit(next);
  }

  void applyConditions(SearchConditions conditions) =>
      _commit(state.copyWith(conditions: conditions));

  void openPlan(String id) {
    final plan = ref
        .read(tripLibraryProvider)
        .requireValue
        .plans
        .where((p) => p.id == id)
        .firstOrNull;
    if (plan == null) return;
    ref.read(tripLibraryProvider.notifier).select(id);
    state = plan;
    ref.read(itineraryEditorProvider.notifier).open();
  }

  void createItinerary({
    required SearchConditions conditions,
    required String destination,
    required int departureMinutes,
    required List<Experience> stops,
  }) {
    if (stops.isEmpty) return;
    _commit(
      TripState(
        conditions: conditions,
        destination: destination,
        travelDate: conditions.resolveDate(),
        departureMinutes: departureMinutes,
        saved: stops,
        stops: stops,
      ),
    );
    ref.read(itineraryEditorProvider.notifier).open();
  }

  void applySearchFilters(SearchConditions filters) {
    // Keep the current saved plan intact until the new search saves a card.
    state = TripState(conditions: filters, travelDate: filters.resolveDate());
  }

  void updateSearchFilters(SearchConditions filters) {
    final next = state.copyWith(
      conditions: filters,
      travelDate: filters.resolveDate(),
      transportSelections: const [],
    );
    if (state.saved.isEmpty && state.stops.isEmpty) {
      state = next;
    } else {
      _commit(next);
    }
  }

  void save(Experience e) {
    ref.read(tripLibraryProvider.notifier).saveExperience(e);
    if (!state.contains(e) || !state.stops.any((spot) => spot.id == e.id)) {
      _commit(
        state.copyWith(
          saved: state.contains(e) ? state.saved : [...state.saved, e],
          stops: state.stops.any((spot) => spot.id == e.id)
              ? state.stops
              : [...state.stops, e],
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
    if (!state.stops.any((spot) => spot.id == e.id)) {
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
    _commit(state.copyWith(stops: stops, transportSelections: []));
  }

  void selectTransport(TransportSelection selection) => _commit(
    state.copyWith(
      ai: {...state.ai, if (state.ai['result'] != null) 'enabled': false},
      transportSelections: [
        ...state.transportSelections.where(
          (s) => s.from != selection.from || s.to != selection.to,
        ),
        selection,
      ],
    ),
  );
  void clearTransport(String from, String to) => _commit(
    state.copyWith(
      transportSelections: state.transportSelections
          .where((s) => s.from != from || s.to != to)
          .toList(),
    ),
  );
  void setStay(String id, int minutes) =>
      _commit(state.copyWith(stayMinutes: {...state.stayMinutes, id: minutes}));
  void setDate(DateTime date) => _commit(
    state.copyWith(
      travelDate: DateTime(date.year, date.month, date.day),
      conditions: state.conditions.copyWith(
        dateChoice: DateChoice.fixed,
        fixedDate: date,
      ),
    ),
  );
  void setDepartureMinutes(int minutes) {
    if (minutes < 0 || minutes >= 1440) throw ArgumentError.value(minutes);
    _commit(state.copyWith(departureMinutes: minutes));
  }

  void setOrigin(String origin) =>
      applyConditions(state.conditions.copyWith(origin: origin));
  void setTravelMode(TravelMode mode) =>
      applyConditions(state.conditions.copyWith(transport: mode));
}
