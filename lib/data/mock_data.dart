import '../model/experience.dart';

const moods = [
  ('おいしいものを食べて幸せになりたい', '食'),
  ('知らない世界に驚きたい', '歴史'),
  ('のんびり癒やされたい', '自然'),
  ('誰かと楽しい思い出を作りたい', '街歩き'),
  ('普段できない体験をしたい', 'ものづくり'),
  ('美しい景色に感動したい', '絶景'),
];
const experiences = [
  Experience(
    'melon',
    'ひとくちの甘さに、土地の物語。',
    '夕張',
    '食',
    '夕張メロンを入口に、育てる人と土地に思いを巡らせる。',
    '短い夏の光と、毎日の手仕事。その積み重ねが、一玉の香りになります。直売所を巡る旅を想像してみませんか。',
    '畑の風景を知ると、いつものひとくちが少し変わるかもしれません。農園見学・試食は未確認の体験例です。',
    'photo-1571575173700-afb9492e6a50',
    60,
  ),
  Experience(
    'coal',
    '暗闇の先に、街の記憶がある。',
    '夕張',
    '歴史',
    '炭鉱文化に触れ、北海道を支えた人々の暮らしを想像する。',
    '山あいの街に、かつて響いた働く人の足音。石炭の歴史をたどれば、風景の中に暮らしの記憶が浮かびます。',
    '産業の物語は、鉄道や食文化にもつながっています。坑道への入場や見学内容は確認していないサンプルです。',
    'photo-1518837695005-2083093ee35b',
    90,
  ),
  Experience(
    'lake',
    '湖に沈んだ時間を、眺める。',
    '夕張・シューパロ湖',
    '自然',
    '水面と山並みが描く、静かな風景に出会う。',
    '水位や季節によって表情を変える湖。耳を澄ませながら、かつてここにあった暮らしを想像するひととき。',
    '同じ場所でも季節で違う景色に。立入可能な場所や交通手段は訪問前の確認が必要です。',
    'photo-1472396961693-142e6e269027',
    60,
  ),
  Experience(
    'otaru',
    '路地の先で、港町の素顔に会う。',
    '小樽',
    '街歩き',
    '運河から少し離れて、古い建物と坂道を歩く。',
    '海へ続く坂道、倉庫の壁、静かな路地。地図の有名な点と点の間に、自分だけの発見が待っています。',
    '建物の細部を見つめるだけでも、交易の歴史を感じる街歩きに。',
    'photo-1480796927426-f609979314bd',
    90,
  ),
  Experience(
    'craft',
    '手を動かすと、旅が形になる。',
    '小樽',
    'ものづくり',
    'ガラスの光や職人の仕事に触れる旅のアイデア。',
    '透明な素材に映る色と光。作る過程を知ると、お土産選びにも新しい視点が生まれます。',
    '制作・見学プログラムは未確認の体験例です。予約や開催状況は別途確認が必要です。',
    'photo-1493106641515-6b5631de4bb9',
    90,
  ),
  Experience(
    'b walk',
    '森の呼吸に、歩幅を合わせて。',
    '江別・野幌',
    '自然',
    '身近な森で、音と香りを探す小さな冒険。',
    '木漏れ日の揺れ、足元の葉の音。遠くへ行かなくても、いつもと違う速さで歩くだけで発見があります。',
    '小さな観察を目的にすると、短い散歩も旅になります。',
    'photo-1448375240586-882707db888b',
    75,
  ),
  Experience(
    'bread',
    '焼きたての香りを、旅の目的に。',
    '札幌',
    '食',
    'パンと街歩きで、いつもの街を再発見する。',
    '朝の街で、お気に入りの一品を探す。近くの公園で食べるだけでも、いつもと違う休日の始まりです。',
    '店舗や商品を指定しない、サンプルの旅のアイデアです。',
    'photo-1509440159596-0249088772ff',
    60,
  ),
  Experience(
    'hill',
    '空の広さを、思い出す。',
    '美瑛',
    '絶景',
    '丘の稜線と雲の影を眺める時間。',
    '畑の色、道の曲線、流れる雲。移り変わる光を待つことも、この土地ならではの過ごし方です。',
    '畑は私有地です。公道や指定の展望場所から眺める想定です。',
    'photo-1470770841072-f978cf4d019e',
    60,
  ),
  Experience(
    'river',
    '川のそばに、何もしない時間を。',
    '千歳',
    '自然',
    '水の音を聞きながら、気持ちをほどく。',
    '透明な流れを目で追いかける。予定を詰めずに立ち止まる時間が、旅の記憶になるかもしれません。',
    '水辺の遊歩道を歩く想定。アクティビティ提供を保証するものではありません。',
    'photo-1437482078695-73f5ca6c96e2',
    60,
  ),
  Experience(
    'rail',
    '線路の向こうに、開拓の物語。',
    '三笠',
    '歴史',
    '鉄道と炭鉱のつながりを知る旅。',
    '運ばれたのは石炭だけではなく、人と文化も。鉄道の記憶をたどると、北海道の街がつながって見えてきます。',
    '施設の見学・乗車体験は未確認のサンプルです。',
    'photo-1474487548417-781cb71495f3',
    90,
  ),
];

List<Experience> recommend(String category, List<int> answers) {
  final close = experiences.where((e) => e.category == category).toList();
  final relatedCategory =
      category == '食' && (answers.isEmpty || answers.first == 0)
      ? '歴史'
      : 'ものづくり';
  final related = experiences
      .where((e) => e.category == relatedCategory && e.category != category)
      .toList();
  final unexpected = experiences
      .where((e) => e.category != category && e.category != relatedCategory)
      .toList();
  if (answers.isNotEmpty && answers.last == 1) {
    unexpected.setAll(0, unexpected.reversed.toList());
  }
  final result = <Experience>[];
  while (close.isNotEmpty || related.isNotEmpty || unexpected.isNotEmpty) {
    for (final group in [close, related, unexpected]) {
      if (group.isNotEmpty) result.add(group.removeAt(0));
    }
  }
  return result;
}

List<TransitLeg> sampleTransit(String origin, List<Experience> stops) => [
  for (var i = 0; i < stops.length; i++)
    TransitLeg(
      mode: i == 0 ? 'JR ＋ 路線バス（サンプル）' : '路線バス（サンプル）',
      from: i == 0 ? origin : stops[i - 1].area,
      to: stops[i].area,
      departure: '${8 + i * 2}:10',
      arrival: '${9 + i * 2}:20',
      transfer: i == 0 ? '駅前でバスに乗換・待ち時間20分' : '乗換なしの想定',
      walking: '停留所から徒歩約15分',
      fare: i == 0 ? '約2,000円' : '約400円',
    ),
];
