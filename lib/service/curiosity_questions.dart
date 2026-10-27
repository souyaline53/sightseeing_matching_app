class ChoiceQuestion {
  final String title;
  final List<String> choices;
  final List<int> photos;
  const ChoiceQuestion(this.title, this.choices, this.photos);
}

class CuriosityQuestions {
  static ChoiceQuestion reason(int mood) => switch (mood) {
    0 => const ChoiceQuestion(
      'どちらに惹かれる？',
      ['誰もが知る、とびきりおいしいもの', '地元の人しか知らない、秘密の味'],
      [0, 6],
    ),
    1 => const ChoiceQuestion(
      'どんな驚きに出会いたい？',
      ['街を支えた、大きな歴史', '路地に隠れた、小さな物語'],
      [1, 3],
    ),
    2 => const ChoiceQuestion(
      'どんな時間が心地いい？',
      ['水辺で静かに深呼吸', '森を歩きながらリフレッシュ'],
      [2, 5],
    ),
    3 => const ChoiceQuestion(
      'どんな思い出を残したい？',
      ['みんなでおいしいものを囲む', '初めての景色を一緒に探す'],
      [6, 7],
    ),
    4 => const ChoiceQuestion(
      'どんな初めてに惹かれる？',
      ['自分の手で何かを作る', '知らない土地を探検する'],
      [4, 9],
    ),
    _ => const ChoiceQuestion(
      'どんな景色に心が動く？',
      ['どこまでも広がる空と大地', '水面に映る静かな世界'],
      [7, 2],
    ),
  };
  static ChoiceQuestion broaden(int mood, int reason) {
    const branches = [
      [
        ChoiceQuestion(
          'おいしさの先に、何を知りたい？',
          ['作り手のこだわりを知ってみたい', '食を育てた街の歴史を歩きたい'],
          [4, 1],
        ),
        ChoiceQuestion(
          '秘密の味から、もう一歩。',
          ['土地の手仕事にも触れてみたい', 'その街の知られざる風景を探したい'],
          [4, 3],
        ),
      ],
      [
        ChoiceQuestion(
          '歴史の先に、何を見つけたい？',
          ['今につながる職人の技', '産業が生まれた自然の風景'],
          [4, 2],
        ),
        ChoiceQuestion('小さな物語の続きを探すなら？', ['暮らしに根付いた食文化', '人々が歩いた森や水辺'], [6, 8]),
      ],
      [
        ChoiceQuestion(
          '水辺の静けさから、もう一歩。',
          ['湖と街の記憶を知りたい', '旅先の手仕事に癒やされたい'],
          [1, 4],
        ),
        ChoiceQuestion('森の散歩の後は？', ['土地の味をゆっくり楽しむ', '森と人の暮らしの歴史を知る'], [6, 9]),
      ],
      [
        ChoiceQuestion(
          '食卓の楽しさを、別の体験にも。',
          ['みんなで手仕事に挑戦', '食を育む風景を見に行く'],
          [4, 7],
        ),
        ChoiceQuestion(
          '景色を見つけた、その先は？',
          ['その土地の味を分かち合う', '街の意外な歴史を一緒に探す'],
          [0, 1],
        ),
      ],
      [
        ChoiceQuestion('作る楽しさから、もう一歩。', ['材料が生まれる自然へ', '技が伝わった街の歴史へ'], [5, 9]),
        ChoiceQuestion(
          '探検の途中で寄り道するなら？',
          ['土地ならではの味に出会う', 'ものづくりの文化に触れる'],
          [0, 4],
        ),
      ],
      [
        ChoiceQuestion('大地の風景の奥にあるものは？', ['土地を耕す人の物語', '風景を変えた鉄道の歴史'], [0, 9]),
        ChoiceQuestion('水面の向こうを知るなら？', ['街と湖がつながる歴史', '土地の光を映す手仕事'], [1, 4]),
      ],
    ];
    return branches[mood][reason];
  }
}
