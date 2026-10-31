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
}
