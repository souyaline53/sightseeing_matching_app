/// Interest hints are independent of saved travel filters and profile defaults.
class InterestAnswers {
  final int mood;
  final List<int> choices;
  InterestAnswers({this.mood = 0, List<int> choices = const []})
    : choices = List.unmodifiable(choices);
  bool get complete => choices.length == 2;
}
