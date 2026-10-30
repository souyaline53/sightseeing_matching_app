import 'experience.dart';
import 'travel_catalog.dart';

enum CatalogKind {
  sightseeing('sightseeing_spot', '観光地情報'),
  transit('transit', '交通情報');

  final String collection, label;
  const CatalogKind(this.collection, this.label);
}

class CatalogField {
  final String key, label;
  final bool number, multiline;
  const CatalogField(
    this.key,
    this.label, {
    this.number = false,
    this.multiline = false,
  });
}

List<CatalogField> catalogFields(CatalogKind kind) =>
    kind == CatalogKind.sightseeing
    ? const [
        CatalogField('title', 'タイトル'),
        CatalogField('area', '地域'),
        CatalogField('category', 'カテゴリ'),
        CatalogField('description', '紹介', multiline: true),
        CatalogField('story', 'ストーリー', multiline: true),
        CatalogField('surprise', '意外な魅力', multiline: true),
        CatalogField('minutes', '体験の所要時間（分）', number: true),
        CatalogField('accessMinutes', '移動時間の目安（分・サンプル）', number: true),
        CatalogField('order', '表示順', number: true),
      ]
    : const [
        CatalogField('position', '適用区間（first / following / any）'),
        CatalogField('spotId', '観光地ID（共通の場合は *）'),
        CatalogField('mode', '交通機関'),
        CatalogField('transfer', '乗換情報'),
        CatalogField('walking', '徒歩時間'),
        CatalogField('fare', '推定交通費'),
        CatalogField('departureMinutes', '発車時刻（0時からの分数）', number: true),
        CatalogField('arrivalMinutes', '到着時刻（翌日なら1440以上）', number: true),
        CatalogField('stepMinutes', '後続区間ごとの加算時間（分・サンプル）', number: true),
        CatalogField('note', '注意事項', multiline: true),
        CatalogField('order', '表示順', number: true),
      ];
String? validateCatalogRecord(
  CatalogKind kind,
  String id,
  Map<String, dynamic> data,
) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_ -]{0,79}$').hasMatch(id)) {
    return 'IDは英数字で始まる1〜80文字（英数字・半角スペース・ハイフン・アンダースコア）で指定してください。';
  }
  for (final field in catalogFields(kind)) {
    final value = data[field.key];
    if (field.number) {
      if (value is! int || value < 0 || value > 100000) {
        return '${field.label}は0〜100000の整数で指定してください。';
      }
    } else if (value is! String ||
        value.trim().isEmpty ||
        value.length > 10000) {
      return '${field.label}を1〜10000文字で入力してください。';
    }
  }
  if (kind == CatalogKind.transit) {
    if (!['first', 'following', 'any'].contains(data['position'])) {
      return '適用区間はfirst・following・anyから選択してください。';
    }
    if ((data['arrivalMinutes'] as int) < (data['departureMinutes'] as int)) {
      return '到着時刻は発車時刻以降にしてください。';
    }
    if (data['spotId'] != '*' &&
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9_ -]{0,79}$',
        ).hasMatch(data['spotId'] as String)) {
      return '観光地IDを確認してください。';
    }
  }
  return null;
}

class CatalogRecord {
  final String id;
  final CatalogKind kind;
  final Map<String, dynamic> data;
  CatalogRecord(this.id, this.kind, Map<String, dynamic> data)
    : data = Map.unmodifiable(data);
  String get title =>
      data[kind == CatalogKind.sightseeing ? 'title' : 'mode'] as String;
  int get order => data['order'] as int? ?? 1000;
  List<CloudCatalogPhoto> get photos => [
    if ((data['photo'] as String? ?? '').isNotEmpty)
      CloudCatalogPhoto(
        data['photo'] as String,
        data['photoPath'] as String? ?? '',
      ),
    for (var i = 0; i < (data['additionalPhotos'] as List? ?? []).length; i++)
      CloudCatalogPhoto(
        (data['additionalPhotos'] as List)[i] as String,
        i < (data['additionalPhotoPaths'] as List? ?? []).length
            ? (data['additionalPhotoPaths'] as List)[i] as String
            : '',
      ),
  ];
  Experience toExperience() => Experience.fromJson({...data, 'id': id});
  TransitSample toTransit() => TransitSample(
    id: id,
    position: data['position'] as String,
    spotId: data['spotId'] as String,
    mode: data['mode'] as String,
    transfer: data['transfer'] as String,
    walking: data['walking'] as String,
    fare: data['fare'] as String,
    departureMinutes: data['departureMinutes'] as int,
    arrivalMinutes: data['arrivalMinutes'] as int,
    stepMinutes: data['stepMinutes'] as int,
    photo: data['photo'] as String? ?? '',
    note: data['note'] as String,
  );
}

class CloudCatalogPhoto {
  final String url, path;
  const CloudCatalogPhoto(this.url, this.path);
}
