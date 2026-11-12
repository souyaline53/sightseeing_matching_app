import '../model/interest_answers.dart';
import '../data/catalog_data.dart';
import 'settings_state.dart';
import 'conditions_step_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../service/curiosity_questions.dart';
import '../model/experience.dart';
import '../service/ai_matching_service.dart';
import 'trip_state.dart';

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
  final bool aiLoading;
  final String? aiError;
  final Map<String, String> recommendationReasons;
  final List<Experience> deck;
  DiscoveryState({
    this.step = 0,
    this.question = 0,
    this.index = 0,
    this.interests = const InterestAnswers(),
    this.aiLoading = false,
    this.aiError,
    this.recommendationReasons = const {},
    List<Experience> deck = const [],
  }) : deck = List.unmodifiable(deck);
  DiscoveryState copyWith({
    int? step,
    int? question,
    int? index,
    InterestAnswers? interests,
    List<Experience>? deck,
    bool? aiLoading,
    String? aiError,
    Map<String, String>? recommendationReasons,
  }) => DiscoveryState(
    step: step ?? this.step,
    question: question ?? this.question,
    index: index ?? this.index,
    interests: interests ?? this.interests,
    deck: deck ?? this.deck,
    aiLoading: aiLoading ?? this.aiLoading,
    aiError: aiError,
    recommendationReasons: recommendationReasons ?? this.recommendationReasons,
  );
}

final discoveryProvider = NotifierProvider<DiscoveryNotifier, DiscoveryState>(
  DiscoveryNotifier.new,
);

class DiscoveryNotifier extends Notifier<DiscoveryState> {
  int _requestVersion = 0;
  Map<String, dynamic>? _lastContext;
  @override
  DiscoveryState build() => DiscoveryState();
  void reset() {
    _requestVersion++;
    state = state.copyWith(step: 0, aiLoading: false);
  }

  // Existing preset entry point now starts with the three questions too.
  void startConditions() => beginSearch();
  void beginSearch() {
    _requestVersion++;
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
    _requestVersion++;
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

  Future<void> showExplore({
    List<String>? savedSpotIds,
    bool retry = false,
    Map<String, dynamic>? travelContext,
  }) async {
    final version = ++_requestVersion;
    final input = aiQuestionInput(state.interests);
    final context = retry && _lastContext != null
        ? _lastContext!
        : travelContext ??
              aiTravelContext(
                ref.read(searchDraftProvider),
                savedSpotIds ?? ref.read(tripProvider).saved.map((e) => e.id),
              );
    _lastContext = context;
    state = state.copyWith(
      step: 3,
      index: 0,
      deck: [],
      aiLoading: true,
      recommendationReasons: {},
    );
    try {
      final results = await ref
          .read(aiMatchingServiceProvider)
          .getRecommendations(
            interests: input['interests']!,
            mood: input['mood']!,
            travelContext: context,
          );
      final catalog = await ref.read(catalogProvider.future);
      if (!ref.mounted || version != _requestVersion) return;
      final byId = {for (final e in catalog.experiences) e.id: e};
      final deck = [
        for (final result in results)
          if (byId.containsKey(result.spotId)) byId[result.spotId]!,
      ];
      if (results.isNotEmpty && deck.isEmpty) {
        throw StateError('推薦先のデータがありません。');
      }
      state = state.copyWith(
        deck: deck,
        aiLoading: false,
        recommendationReasons: {for (final r in results) r.spotId: r.reason},
      );
    } catch (error) {
      if (!ref.mounted || version != _requestVersion) return;
      state = state.copyWith(aiLoading: false, aiError: aiMatchingError(error));
    }
  }

  void goTo(int index) {
    if (index >= 0 && index <= state.deck.length) {
      state = state.copyWith(index: index);
    }
  }

  void previous() {
    if (state.index > 0) goTo(state.index - 1);
  }

  void advance() {
    if (state.index < state.deck.length) goTo(state.index + 1);
  }
}
