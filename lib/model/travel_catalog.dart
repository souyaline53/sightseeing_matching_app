import 'experience.dart';

class TravelCatalog {
  final List<Experience> experiences;
  TravelCatalog({required List<Experience> experiences})
    : experiences = List.unmodifiable(experiences);
}
