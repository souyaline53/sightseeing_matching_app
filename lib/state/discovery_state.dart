import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../data/mock_data.dart';
import '../model/experience.dart';

class DiscoveryState {
  final int step, mood, question, index;
  final List<int> answers;
  final List<Experience> deck;
  DiscoveryState({
    this.step = 0,
    this.mood = 0,
    this.question = 0,
    this.index = 0,
    List<int> answers = const [],
    List<Experience> deck = const [],
  }) : answers = List.unmodifiable(answers),
       deck = List.unmodifiable(deck);
  DiscoveryState copyWith({
    int? step,
    int? mood,
    int? question,
    int? index,
    List<int>? answers,
    List<Experience>? deck,
  }) => DiscoveryState(
    step: step ?? this.step,
    mood: mood ?? this.mood,
    question: question ?? this.question,
    index: index ?? this.index,
    answers: answers ?? this.answers,
    deck: deck ?? this.deck,
  );
}

final discoveryProvider = NotifierProvider<DiscoveryNotifier, DiscoveryState>(
  DiscoveryNotifier.new,
);

class DiscoveryNotifier extends Notifier<DiscoveryState> {
  @override
  DiscoveryState build() => DiscoveryState();
  void reset() => state = DiscoveryState(mood: state.mood);
  void selectMood(int mood) => state = state.copyWith(mood: mood);
  void startQuestions() => state = state.copyWith(step: 1);
  void answer(int choice) {
    final answers = [...state.answers, choice];
    state = state.question == 0
        ? state.copyWith(question: 1, answers: answers)
        : state.copyWith(
            step: 2,
            index: 0,
            answers: answers,
            deck: recommend(moods[state.mood].$2, answers),
          );
  }

  void advance() {
    if (state.index < state.deck.length) {
      state = state.copyWith(index: state.index + 1);
    }
  }

  void restartDeck() => state = state.copyWith(index: 0);
}
