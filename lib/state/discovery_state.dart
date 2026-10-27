import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../data/mock_data.dart';
import '../model/experience.dart';
import '../service/recommendation_service.dart';

// step: home=0, conditions=1, questions=2, explore=3.
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
  void reset() => state = state.copyWith(step: 0);
  void startConditions() => state = state.copyWith(step: 1);
  void startQuestions() => state = state.copyWith(step: 2, question: 0);
  void back() {
    if (state.step == 3) {
      state = state.copyWith(step: 2, question: 2);
    } else if (state.step == 2 && state.question > 0) {
      state = state.copyWith(question: state.question - 1);
    } else {
      state = state.copyWith(step: state.step > 0 ? state.step - 1 : 0);
    }
  }

  void selectMood(int mood) => state = state.copyWith(
    mood: mood,
    question: 1,
    answers: mood == state.mood ? state.answers : [],
  );
  void answer(int choice) {
    final position = state.question - 1;
    if (position < 0) return;
    final answers = [...state.answers];
    if (answers.length > position) {
      if (answers[position] != choice) {
        answers.removeRange(position, answers.length);
        answers.add(choice);
      }
    } else {
      answers.add(choice);
    }
    state = state.copyWith(answers: answers, question: 2);
  }

  void showExplore() => state = state.copyWith(
    step: 3,
    index: 0,
    deck: RecommendationService().recommend(
      moods[state.mood].$2,
      state.answers,
    ),
  );
  void goTo(int index) {
    if (index >= 0 && index < state.deck.length) {
      state = state.copyWith(index: index);
    }
  }

  void advance() {
    if (state.deck.isNotEmpty) goTo((state.index + 1) % state.deck.length);
  }

  void removeCard(String id) {
    final deck = state.deck.where((e) => e.id != id).toList();
    state = state.copyWith(
      deck: deck,
      index: deck.isEmpty ? 0 : state.index.clamp(0, deck.length - 1),
    );
  }
}
