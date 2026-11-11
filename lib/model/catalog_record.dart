import 'admin_transport_fields.dart';
import 'experience.dart';

enum CatalogKind {
  sightseeing('sightseeing_spot', '観光地情報'),
  departure('departure_places', '出発地情報');

  final String collection, label;
  const CatalogKind(this.collection, this.label);
}

class CatalogField {
  final String key, label;
  final bool number, multiline, optional;
  final int maxLength;
  const CatalogField(
    this.key,
    this.label, {
    this.number = false,
    this.multiline = false,
    this.optional = false,
    this.maxLength = 10000,
  });
}

List<CatalogField> catalogFields(CatalogKind kind) =>
    kind == CatalogKind.departure
    ? const [CatalogField('address', '住所', optional: true, maxLength: 500)]
    : const [
        CatalogField('name', '観光地名称', optional: true, maxLength: 120),
        CatalogField('title', '紹介タイトル'),
        CatalogField('area', '地域'),
        CatalogField('address', '住所', optional: true, maxLength: 500),
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
  if (kind == CatalogKind.departure &&
      (id.trim() != id ||
          id.isEmpty ||
          id.length > 80 ||
          id.contains('/') ||
          id == '.' ||
          id == '..' ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(id))) {
    return 'IDはスラッシュ・制御文字を含まない1〜80文字で指定してください。';
  }
  if (kind == CatalogKind.sightseeing &&
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_ -]{0,79}$').hasMatch(id)) {
    return 'IDは英数字で始まる1〜80文字（英数字・半角スペース・ハイフン・アンダースコア）で指定してください。';
  }
  for (final field in catalogFields(kind)) {
    final value = data[field.key];
    if (field.optional && !data.containsKey(field.key)) continue;
    if (field.number) {
      if (value is! int || value < 0 || value > 100000) {
        return '${field.label}は0〜100000の整数で指定してください。';
      }
    } else if (value is! String ||
        (!field.optional && value.trim().isEmpty) ||
        value.length > field.maxLength) {
      return '${field.label}は文字列で${field.maxLength}文字以内にしてください。';
    }
  }
  final lat = data['latitude'], lon = data['longitude'];
  if ((kind == CatalogKind.departure || lat != null || lon != null) &&
      (lat is! num ||
          lon is! num ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat < -90 ||
          lat > 90 ||
          lon < -180 ||
          lon > 180)) {
    return '緯度は−90〜90、経度は−180〜180で指定してください。';
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
  String get title =>
      kind == CatalogKind.departure ? id : data['title'] as String;
  int get order => data['order'] as int? ?? 1000;
  String get name => data['name'] as String? ?? '';
  String get displayName => name.trim().isNotEmpty ? name.trim() : title;
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
