import 'admin_transport_fields.dart';
import 'experience.dart';

enum CatalogKind {
  sightseeing('sightseeing_spot', '観光地情報');

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

List<CatalogField> catalogFields(CatalogKind kind) => const [
  CatalogField('title', 'タイトル'),
  CatalogField('area', '地域'),
  CatalogField('category', 'カテゴリ'),
  CatalogField('description', '紹介', multiline: true),
  CatalogField('story', 'ストーリー', multiline: true),
  CatalogField('surprise', '意外な魅力', multiline: true),
  CatalogField('minutes', '体験の所要時間（分）', number: true),
  CatalogField('accessMinutes', '検索用の移動時間目安（分・サンプル）', number: true),
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
  try {
    validateAdminFields([accessStopsField], data);
  } on FormatException catch (e) {
    return e.message;
  }
  return null;
}

class CatalogRecord {
  final String id;
  final CatalogKind kind;
  final Map<String, dynamic> data;
  CatalogRecord(this.id, this.kind, Map<String, dynamic> data)
    : data = Map.unmodifiable(data);
  String get title => data['title'] as String;
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
}

class CloudCatalogPhoto {
  final String url, path;
  const CloudCatalogPhoto(this.url, this.path);
}
