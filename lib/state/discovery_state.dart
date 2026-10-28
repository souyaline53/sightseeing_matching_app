import '../model/interest_answers.dart';
import 'settings_state.dart';
import 'conditions_step_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../data/mock_data.dart';
import '../model/experience.dart';
import '../service/recommendation_service.dart';

// step: home=0, conditions=1, questions=2, explore=3.
class DiscoveryState {
  final int step, question, index;
  final InterestAnswers interests;
  int get mood => interests.mood;
  List<int> get answers => interests.choices;
  final List<Experience> deck;
  DiscoveryState({
    this.step = 0,
    int mood = 0,
    bool moodSelected = false,
    this.question = 0,
    this.index = 0,
    List<int> answers = const [],
    List<Experience> deck = const [],
    InterestAnswers? interests,
  }) : interests =
           interests ??
           InterestAnswers(
             mood: mood,
             moodSelected: moodSelected,
             choices: answers,
           ),
       deck = List.unmodifiable(deck);
  DiscoveryState copyWith({
    int? step,
    int? mood,
    bool? moodSelected,
    int? question,
    int? index,
    List<int>? answers,
    List<Experience>? deck,
  }) => DiscoveryState(
    step: step ?? this.step,
    mood: mood ?? this.mood,
    moodSelected: moodSelected ?? interests.moodSelected,
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
  // Existing preset entry point now starts with the three questions too.
  void startConditions() => beginSearch();
  void beginSearch() {
    ref.read(searchDraftProvider.notifier).prepareSearch();
    ref.read(conditionsStepProvider.notifier).reset();
    state = DiscoveryState(step: 2);
  }

  void showConditions() {
    if (!state.interests.complete) return;
    ref.read(conditionsStepProvider.notifier).reset();
    state = state.copyWith(step: 1);
  }

  void startQuestions() => state = state.copyWith(step: 2, question: 0);
  void back() {
    if (state.step == 3) {
      state = state.copyWith(step: 1);
    } else if (state.step == 1 && ref.read(conditionsStepProvider) > 0) {
      ref.read(conditionsStepProvider.notifier).back();
    } else if (state.step == 1) {
      state = state.copyWith(step: 2, question: 2);
    } else if (state.step == 2 && state.question > 0) {
      state = state.copyWith(question: state.question - 1);
    } else {
      state = state.copyWith(step: 0);
    }
  }

  void selectMood(int mood) => state = state.copyWith(
    mood: mood,
    moodSelected: true,
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
      filters: ref.read(searchDraftProvider),
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
}
