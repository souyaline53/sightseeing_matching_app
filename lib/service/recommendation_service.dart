import '../model/search_settings.dart';
import '../model/interest_answers.dart';
import 'mock_access_ranking.dart';
import 'curiosity_questions.dart';
import '../data/mock_data.dart';
import '../model/experience.dart';

class RecommendationService {
  final List<Experience> catalog;
  const RecommendationService({this.catalog = experiences});
  List<Experience> recommendFor(
    InterestAnswers answers, {
    SearchFilters? filters,
  }) {
    if (!CuriosityQuestions.valid(answers)) return const [];
    final hints = CuriosityQuestions.hints(answers);
    // Only registered data is eligible, including when the catalog is empty.
    final available = {
      for (final experience in catalog) experience.id: experience,
    }.values.toList();
    final quest = available
        .where((e) => hints.questGenres.contains(e.category))
        .toList();
    final close = available
        .where((e) => hints.closeGenres.contains(e.category))
        .toList();
    final adjacent = available
        .where((e) => hints.adjacentGenres.contains(e.category))
        .toList();
    final known = {
      ...hints.closeGenres,
      ...hints.questGenres,
      ...hints.adjacentGenres,
    };
    final unexpected = available
        .where((e) => !known.contains(e.category))
        .toList();
    if (filters != null) {
      final ranking = MockAccessRanking();
      for (final group in [quest, close, adjacent, unexpected]) {
        final originalOrder = [...group];
        group.sort((a, b) {
          final order = ranking
              .score(a, filters)
              .compareTo(ranking.score(b, filters));
          return order == 0
              ? originalOrder.indexOf(a).compareTo(originalOrder.indexOf(b))
              : order;
        });
      }
    }
    final result = <Experience>[];
    final used = <String>{};
    // Give the chosen quest a head start while reserving discovery slots.
    final cycle = [quest, close, unexpected, quest, adjacent, close];
    while ([quest, close, adjacent, unexpected].any((g) => g.isNotEmpty)) {
      for (final group in cycle) {
        while (group.isNotEmpty) {
          final e = group.removeAt(0);
          if (used.add(e.id)) {
            result.add(e);
            break;
          }
        }
      }
    }
    return result;
  }

  // Compatibility adapter for the previous category/index-based API.
  List<Experience> recommend(
    String category,
    List<int> choices, {
    SearchFilters? filters,
  }) {
    final moodIndex = moods.indexWhere((m) => m.$2 == category);
    final mood = CuriosityQuestions.moods.elementAtOrNull(moodIndex);
    if (mood == null || choices.length < 2) return const [];
    final reason = CuriosityQuestions.reasonFor(
      mood.id,
    ).options.elementAtOrNull(choices[0]);
    final quest = CuriosityQuestions.questsFor(
      mood.id,
      reason?.id,
    ).options.elementAtOrNull(choices[1]);
    return recommendFor(
      InterestAnswers(
        moodId: mood.id,
        reasonId: reason?.id,
        questId: quest?.id,
      ),
      filters: filters,
    );
  }
}
