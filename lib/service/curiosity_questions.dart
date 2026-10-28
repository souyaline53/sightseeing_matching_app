import '../model/interest_answers.dart';

class MoodChoice {
  final String id, label, photoId;
  final List<String> genres;
  const MoodChoice(this.id, this.label, this.photoId, this.genres);
}

class QuestionOption {
  final String id, title, photoId;
  final String? description;
  final List<String> genres;
  const QuestionOption(
    this.id,
    this.title,
    this.photoId,
    this.genres, {
    this.description,
  });
}

class ReasonOption extends QuestionOption {
  final String tendencyId, questSetId, questPrompt;
  const ReasonOption(
    super.id,
    super.title,
    super.photoId,
    super.genres,
    this.tendencyId,
    this.questSetId,
    this.questPrompt,
  );
}

class ChoiceQuestion {
  final String title;
  final List<QuestionOption> options;
  const ChoiceQuestion(this.title, this.options);
  List<String> get choices =>
      options.map((o) => o.title).toList(growable: false);
}

class CuriosityQuestions {
  static const moods = [
    MoodChoice('food', 'おいしいものを食べて幸せになりたい', 'melon', ['食']),
    MoodChoice('discovery', '知らない世界にワクワクしたい', 'coal', ['歴史', 'ものづくり']),
    MoodChoice('relax', '日常を忘れてリフレッシュしたい', 'lake', ['自然', '絶景']),
    MoodChoice('fun', '思いっきり楽しみたい', 'craft', ['街歩き', 'ものづくり']),
  ];
  static const _reasons = {
    'food': ChoiceQuestion('どんな出会いが一番うれしい？', [
      ReasonOption(
        'food_luxury',
        '一度は食べたい、とびきり贅沢な一品',
        'melon',
        ['食', '絶景'],
        'senses',
        'senses',
        '特別なおいしさの余韻に、何を加えたい？',
      ),
      ReasonOption(
        'food_hidden',
        '地元の人だけが知る、隠れた名物',
        'bread',
        ['食', '街歩き'],
        'roots',
        'roots',
        'その街にもう一つ秘密があるとしたら？',
      ),
      ReasonOption(
        'food_maker',
        '作り手のこだわりが詰まった、特別な味',
        'melon',
        ['食', 'ものづくり'],
        'craftsmanship',
        'stories',
        'そのこだわりの先に、何があると思う？',
      ),
    ]),
    'discovery': ChoiceQuestion('どんな発見に惹かれる？', [
      ReasonOption(
        'discovery_space',
        '普段は入れない、不思議な空間',
        'coal',
        ['歴史'],
        'mystery',
        'hidden',
        '不思議な空間の向こうに、何を探したい？',
      ),
      ReasonOption(
        'discovery_story',
        '昔の人々が残した、知られざる物語',
        'rail',
        ['歴史', '街歩き'],
        'story',
        'stories',
        '昔の物語が、今の暮らしにつながるなら？',
      ),
      ReasonOption(
        'discovery_landscape',
        '自然が生み出した、想像を超える景色',
        'hill',
        ['自然', '絶景'],
        'senses',
        'senses',
        '驚く景色の奥に、何を見つけたい？',
      ),
    ]),
    'relax': ChoiceQuestion('どんな時間を過ごしたい？', [
      ReasonOption(
        'relax_quiet',
        '静かな場所で、景色を眺める',
        'lake',
        ['自然', '絶景'],
        'senses',
        'senses',
        '静かな景色から、小さく寄り道するなら？',
      ),
      ReasonOption(
        'relax_warm',
        '温かい場所で、ゆっくりくつろぐ',
        'bread',
        ['食', '街歩き'],
        'story',
        'stories',
        'くつろぐ時間に、もう一つ物語を添えるなら？',
      ),
      ReasonOption(
        'relax_wander',
        '自然の中で、気の向くまま歩く',
        'b walk',
        ['自然', '街歩き'],
        'adventure',
        'adventure',
        '気の向くまま歩いた先で、何に出会いたい？',
      ),
    ]),
    'fun': ChoiceQuestion('どんな楽しさを求める？', [
      ReasonOption(
        'fun_active',
        '体を動かして、思いきり遊ぶ',
        'b walk',
        ['自然', '街歩き'],
        'adventure',
        'adventure',
        '体を動かす楽しさを、別の冒険にも広げるなら？',
      ),
      ReasonOption(
        'fun_together',
        '誰かと一緒に、新しいことに挑戦する',
        'craft',
        ['ものづくり', '街歩き'],
        'craftsmanship',
        'stories',
        '一緒に挑戦するなら、どんな世界を覗いてみたい？',
      ),
      ReasonOption(
        'fun_photo',
        '思わず写真を撮りたくなる場所に行く',
        'hill',
        ['絶景', '街歩き'],
        'mystery',
        'hidden',
        '写真の奥に隠れた物語も探すなら？',
      ),
    ]),
  };
  // Five reusable sets cover all twelve Q1×Q2 branches. These are prompts,
  // never promises of bookable activities or generated destination records.
  static const _quests = {
    'roots': [
      QuestionOption('roots_origin', '作り手の秘密を探る', 'melon', [
        '食',
        '自然',
      ], description: '食べ物が育つ場所を見てみたい'),
      QuestionOption('roots_history', '街の意外な歴史を探る', 'coal', [
        '歴史',
      ], description: 'その街の意外な歴史を知りたい'),
      QuestionOption('roots_view', '地元だけの景色を探す', 'lake', [
        '自然',
        '絶景',
      ], description: '地元の人しか知らない景色を探したい'),
    ],
    'hidden': [
      QuestionOption(
        'hidden_underground',
        '地下に眠る世界を探る',
        'coal',
        ['歴史'],
        description: '暗闇の先に残る、人々の記憶に触れてみたい',
      ),
      QuestionOption('hidden_hands', '光をつくる手仕事を探る', 'craft', [
        'ものづくり',
      ], description: 'ふだん見過ごす技と素材の秘密を知りたい'),
      QuestionOption('hidden_water', 'まだ知らない水辺を探す', 'river', [
        '自然',
        '絶景',
      ], description: '日常から少し離れた、水の風景を見つけたい'),
    ],
    'stories': [
      QuestionOption('stories_craft', '受け継がれる技を探る', 'craft', [
        'ものづくり',
      ], description: '作る楽しさと、職人のこだわりに触れてみたい'),
      QuestionOption('stories_taste', '暮らしに残る味を探す', 'bread', [
        '食',
      ], description: 'その土地で愛される味の背景を知りたい'),
      QuestionOption('stories_land', '風景に隠れた記憶を探る', 'lake', [
        '自然',
        '歴史',
      ], description: '景色の向こうにあった暮らしを想像したい'),
    ],
    'senses': [
      QuestionOption('senses_water', '水の風景を見つける', 'river', [
        '自然',
        '絶景',
      ], description: '音や光に目を向けて、いつもと違う景色を探したい'),
      QuestionOption('senses_craft', '土地の光を手仕事に探す', 'craft', [
        'ものづくり',
      ], description: 'きれいなものが生まれる過程を知りたい'),
      QuestionOption('senses_memory', '静かな街の記憶を探る', 'rail', [
        '歴史',
        '街歩き',
      ], description: 'にぎわいの跡をたどって、意外な物語に出会いたい'),
    ],
    'adventure': [
      QuestionOption('adventure_craft', '初めての手仕事に近づく', 'craft', [
        'ものづくり',
      ], description: '自分の手で形にする楽しさを覗いてみたい'),
      QuestionOption('adventure_lanes', '路地の向こうを探検する', 'otaru', [
        '街歩き',
        '歴史',
      ], description: '歩くほどに見えてくる、街の秘密を探したい'),
      QuestionOption('adventure_flavor', '旅先の味で冒険する', 'melon', [
        '食',
      ], description: '知らなかった味から、土地の物語を見つけたい'),
    ],
  };

  static MoodChoice? moodFor(String? id) =>
      moods.where((m) => m.id == id).firstOrNull;
  static ChoiceQuestion reasonFor(String? moodId) =>
      _reasons[moodId] ?? const ChoiceQuestion('', []);
  static ReasonOption? reasonOption(String? moodId, String? reasonId) =>
      reasonFor(moodId).options
          .whereType<ReasonOption>()
          .where((r) => r.id == reasonId)
          .firstOrNull;
  static ChoiceQuestion questsFor(String? moodId, String? reasonId) {
    final reason = reasonOption(moodId, reasonId);
    return reason == null
        ? const ChoiceQuestion('', [])
        : ChoiceQuestion(reason.questPrompt, _quests[reason.questSetId]!);
  }

  static QuestionOption? questOption(InterestAnswers answers) => questsFor(
    answers.moodId,
    answers.reasonId,
  ).options.where((q) => q.id == answers.questId).firstOrNull;
  static bool valid(InterestAnswers answers) =>
      moodFor(answers.moodId) != null &&
      reasonOption(answers.moodId, answers.reasonId) != null &&
      questOption(answers) != null;
  static InterestHints hints(InterestAnswers answers) => InterestHints(
    moodId: answers.moodId ?? '',
    tendencyId:
        reasonOption(answers.moodId, answers.reasonId)?.tendencyId ?? '',
    closeGenres: moodFor(answers.moodId)?.genres ?? const [],
    adjacentGenres:
        reasonOption(answers.moodId, answers.reasonId)?.genres ?? const [],
    questGenres: questOption(answers)?.genres ?? const [],
  );

  // Index adapters retain compatibility for older callers; IDs are authoritative.
  static ChoiceQuestion reason(int mood) =>
      reasonFor(moods.elementAtOrNull(mood)?.id);
  static ChoiceQuestion broaden(int mood, int reason) {
    final id = moods.elementAtOrNull(mood)?.id;
    return questsFor(id, reasonFor(id).options.elementAtOrNull(reason)?.id);
  }
}
