import '../model/search_settings.dart';
import 'mock_access_ranking.dart';
import 'curiosity_questions.dart';
import '../data/mock_data.dart';
import '../model/experience.dart';

class RecommendationService {
  List<Experience> recommend(
    String category,
    List<int> answers, {
    SearchFilters? filters,
  }) {
    final close = experiences.where((e) => e.category == category).toList();
    final mood = moods.indexWhere((m) => m.$2 == category);
    final reason = answers.isEmpty ? 0 : answers.first;
    final broadening = answers.length < 2 ? 0 : answers[1];
    final target = CuriosityQuestions.broaden(mood < 0 ? 0 : mood, reason);
    final relatedCategory = experiences[target.photos[broadening]].category;
    final related = experiences
        .where((e) => e.category == relatedCategory && e.category != category)
        .toList();
    final unexpected = experiences
        .where((e) => e.category != category && e.category != relatedCategory)
        .toList();
    if (reason == 1 && unexpected.length > 1) {
      unexpected.add(unexpected.removeAt(0));
    }
    if (answers.isNotEmpty && answers.last == 1) {
      unexpected.setAll(0, unexpected.reversed.toList());
    }
    if (filters != null) {
      final ranking = MockAccessRanking();
      for (final group in [close, related, unexpected]) {
        final originalOrder = [...group];
        group.sort((a, b) {
          final comparison = ranking
              .score(a, filters)
              .compareTo(ranking.score(b, filters));
          return comparison == 0
              ? originalOrder.indexOf(a).compareTo(originalOrder.indexOf(b))
              : comparison;
        });
      }
    }
    final result = <Experience>[];
    while (close.isNotEmpty || related.isNotEmpty || unexpected.isNotEmpty) {
      for (final group in [close, related, unexpected]) {
        if (group.isNotEmpty) result.add(group.removeAt(0));
      }
    }
    return result;
  }
}
