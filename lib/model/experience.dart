class Experience {
  final String id, title, area, category, description, story, surprise, photo;
  final int minutes, accessMinutes;
  final List<String> additionalPhotos;
  final String photoPath;
  final List<String> additionalPhotoPaths;
  final int order;
  const Experience(
    this.id,
    this.title,
    this.area,
    this.category,
    this.description,
    this.story,
    this.surprise,
    this.photo,
    this.minutes, {
    this.additionalPhotos = const [],
    this.accessMinutes = 120,
    this.photoPath = '',
    this.additionalPhotoPaths = const [],
    this.order = 1000,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'area': area,
    'category': category,
    'description': description,
    'story': story,
    'surprise': surprise,
    'photo': photo,
    'minutes': minutes,
    'additionalPhotos': additionalPhotos,
    'accessMinutes': accessMinutes,
    'photoPath': photoPath,
    'additionalPhotoPaths': additionalPhotoPaths,
    'order': order,
  };
  factory Experience.fromJson(Map<String, dynamic> json) => Experience(
    json['id'] as String,
    json['title'] as String,
    json['area'] as String,
    json['category'] as String,
    json['description'] as String,
    json['story'] as String,
    json['surprise'] as String,
    json['photo'] as String,
    json['minutes'] as int,
    accessMinutes: json['accessMinutes'] as int? ?? 120,
    photoPath: json['photoPath'] as String? ?? '',
    additionalPhotoPaths: (json['additionalPhotoPaths'] as List? ?? [])
        .cast<String>(),
    order: json['order'] as int? ?? 1000,
    additionalPhotos: List.unmodifiable(
      (json['additionalPhotos'] as List? ?? const []).cast<String>(),
    ),
  );
}

class TransitLeg {
  final String mode, from, to, departure, arrival, transfer, walking, fare;
  final String photo, note;
  const TransitLeg({
    required this.mode,
    required this.from,
    required this.to,
    required this.departure,
    required this.arrival,
    required this.transfer,
    required this.walking,
    required this.fare,
    this.photo = '',
    this.note = '',
  });
}
