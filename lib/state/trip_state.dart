import 'package:flutter/foundation.dart';
import '../model/experience.dart';

class TripState extends ChangeNotifier {
  final List<Experience> saved = [];
  final List<Experience> stops = [];
  DateTime date = DateTime.now().add(const Duration(days: 1));
  String origin = '札幌駅';
  bool publicTransport = true;
  bool contains(Experience e) => saved.any((x) => x.id == e.id);
  void save(Experience e) {
    if (!contains(e)) {
      saved.add(e);
      stops.add(e);
      notifyListeners();
    }
  }

  void toggle(Experience e) {
    if (contains(e)) {
      saved.removeWhere((x) => x.id == e.id);
      stops.removeWhere((x) => x.id == e.id);
      notifyListeners();
    } else {
      save(e);
    }
  }

  void addStop(Experience e) {
    if (!stops.contains(e)) {
      stops.add(e);
      notifyListeners();
    }
  }

  void removeStop(Experience e) {
    stops.remove(e);
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    stops.insert(newIndex, stops.removeAt(oldIndex));
    notifyListeners();
  }
}
