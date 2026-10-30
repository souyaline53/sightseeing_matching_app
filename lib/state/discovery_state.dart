import '../model/interest_answers.dart';
import '../data/catalog_data.dart';
import 'settings_state.dart';
import 'conditions_step_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../service/curiosity_questions.dart';
import '../model/experience.dart';
import '../service/recommendation_service.dart';

// step: home=0, conditions=1, questions=2, explore=3.
class DiscoveryState {
  final int step, question, index;
  final InterestAnswers interests;
  int get mood => CuriosityQuestions.moods
      .indexWhere((m) => m.id == interests.moodId)
      .clamp(0, 3);
  List<int> get answers => [
    if (interests.reasonId != null)
      CuriosityQuestions.reasonFor(
        interests.moodId,
      ).options.indexWhere((r) => r.id == interests.reasonId),
    if (interests.questId != null)
      CuriosityQuestions.questsFor(
        interests.moodId,
        interests.reasonId,
      ).options.indexWhere((q) => q.id == interests.questId),
  ];
  final List<Experience> deck;
  DiscoveryState({
    this.step = 0,
    this.question = 0,
    this.index = 0,
    this.interests = const InterestAnswers(),
    List<Experience> deck = const [],
  }) : deck = List.unmodifiable(deck);
  DiscoveryState copyWith({
    int? step,
    int? question,
    int? index,
    InterestAnswers? interests,
    List<Experience>? deck,
  }) => DiscoveryState(
    step: step ?? this.step,
    question: question ?? this.question,
    index: index ?? this.index,
    interests: interests ?? this.interests,
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
    if (!CuriosityQuestions.valid(state.interests)) return;
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

  void selectMoodId(String id) {
    if (CuriosityQuestions.moodFor(id) == null) return;
    state = state.copyWith(
      interests: state.interests.selectMood(id),
      question: 1,
    );
  }

  bool answerId(String id) {
    if (state.question == 1) {
      if (CuriosityQuestions.reasonOption(state.interests.moodId, id) == null) {
        return false;
      }
      state = state.copyWith(
        interests: state.interests.selectReason(id),
        question: 2,
      );
      return true;
    }
    if (state.question == 2) {
      if (!CuriosityQuestions.questsFor(
        state.interests.moodId,
        state.interests.reasonId,
      ).options.any((q) => q.id == id)) {
        return false;
      }
      state = state.copyWith(interests: state.interests.selectQuest(id));
      return true;
    }
    return false;
  }

  void selectMood(int index) {
    final mood = CuriosityQuestions.moods.elementAtOrNull(index);
    if (mood != null) selectMoodId(mood.id);
  }

  void answer(int index) {
    final question = state.question == 1
        ? CuriosityQuestions.reasonFor(state.interests.moodId)
        : CuriosityQuestions.questsFor(
            state.interests.moodId,
            state.interests.reasonId,
          );
    final option = question.options.elementAtOrNull(index);
    if (option != null) answerId(option.id);
  }

  void showExplore() => state = state.copyWith(
    step: 3,
    index: 0,
    deck: RecommendationService(
      catalog: ref.read(catalogProvider).requireValue.experiences,
    ).recommendFor(state.interests, filters: ref.read(searchDraftProvider)),
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
