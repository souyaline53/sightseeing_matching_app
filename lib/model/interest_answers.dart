/// Stable IDs, independent of translated labels and choice ordering.
class InterestAnswers {
  final String? moodId, reasonId, questId;
  const InterestAnswers({this.moodId, this.reasonId, this.questId});
  bool get moodSelected => moodId != null;
  bool get complete => moodId != null && reasonId != null && questId != null;
  List<String> get choices => List.unmodifiable([?reasonId, ?questId]);
  InterestAnswers selectMood(String id) =>
      id == moodId ? this : InterestAnswers(moodId: id);
  InterestAnswers selectReason(String id) =>
      id == reasonId ? this : InterestAnswers(moodId: moodId, reasonId: id);
  InterestAnswers selectQuest(String id) =>
      InterestAnswers(moodId: moodId, reasonId: reasonId, questId: id);
}

class InterestHints {
  final String moodId, tendencyId;
  final List<String> closeGenres, adjacentGenres, questGenres;
  InterestHints({
    required this.moodId,
    required this.tendencyId,
    required List<String> closeGenres,
    required List<String> adjacentGenres,
    required List<String> questGenres,
  }) : closeGenres = List.unmodifiable(closeGenres),
       adjacentGenres = List.unmodifiable(adjacentGenres),
       questGenres = List.unmodifiable(questGenres);
}
