/// Interest hints are independent of saved travel filters and profile defaults.
class InterestAnswers {
  final int mood;
  final bool moodSelected;
  final List<int> choices;
  InterestAnswers({
    this.mood = 0,
    this.moodSelected = false,
    List<int> choices = const [],
  }) : choices = List.unmodifiable(choices);
  bool get complete => moodSelected && choices.length == 2;
}
