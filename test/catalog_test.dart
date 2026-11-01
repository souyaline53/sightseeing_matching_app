import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/catalog_record.dart';
import 'package:sightseeing_matching_app/model/experience.dart';

void main() {
  test('Firestore record preserves fields and cloud photo references', () {
    final record = CatalogRecord('cloud-spot', CatalogKind.sightseeing, {
      'title': '体験',
      'area': '北海道',
      'category': '自然',
      'description': '紹介',
      'story': '物語',
      'surprise': '発見',
      'minutes': 60,
      'accessMinutes': 90,
      'order': 1,
      'photo': 'https://example.test/image.jpg',
      'photoPath': 'catalog/sightseeing_spot/cloud-spot/image.jpg',
      'additionalPhotos': ['https://example.test/other.jpg'],
      'additionalPhotoPaths': ['catalog/sightseeing_spot/cloud-spot/other.jpg'],
    });
    expect(validateCatalogRecord(record.kind, record.id, record.data), isNull);
    expect(record.photos, hasLength(2));
    final spot = Experience.fromJson(record.toExperience().toJson());
    expect(spot.photo, startsWith('https://'));
    expect(spot.additionalPhotoPaths, hasLength(1));
  });
  test(
    'place name stays separate from the promotional title and survives serialization',
    () {
      const spot = Experience(
        'id',
        '興味を惹く長い紹介文章',
        '地域',
        '自然',
        '紹介',
        '物語',
        '発見',
        '',
        60,
        name: '○○公園',
      );
      expect(spot.displayName, '○○公園');
      final restored = Experience.fromJson(spot.toJson());
      expect(restored.name, '○○公園');
      expect(restored.title, '興味を惹く長い紹介文章');
      final legacy = spot.toJson()..remove('name');
      expect(Experience.fromJson(legacy).displayName, spot.title);
      expect(
        Experience.fromJson({...legacy, 'name': '  '}).displayName,
        spot.title,
      );
    },
  );
  test('optional legacy name accepts strings only and limits length', () {
    final record = CatalogRecord('cloud-spot', CatalogKind.sightseeing, {
      'title': '紹介文',
      'area': '地域',
      'category': '自然',
      'description': '紹介',
      'story': '物語',
      'surprise': '発見',
      'minutes': 60,
      'accessMinutes': 90,
      'order': 0,
    });
    expect(validateCatalogRecord(record.kind, record.id, record.data), isNull);
    expect(
      validateCatalogRecord(record.kind, record.id, {
        ...record.data,
        'name': '○○公園',
      }),
      isNull,
    );
    expect(
      validateCatalogRecord(record.kind, record.id, {
        ...record.data,
        'name': 123,
      }),
      isNotNull,
    );
    expect(
      validateCatalogRecord(record.kind, record.id, {
        ...record.data,
        'name': null,
      }),
      isNotNull,
    );
    expect(
      validateCatalogRecord(record.kind, record.id, {
        ...record.data,
        'name': 'あ' * 121,
      }),
      isNotNull,
    );
  });
}
