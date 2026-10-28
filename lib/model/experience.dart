class Experience {
  final String id, title, area, category, description, story, surprise, photo;
  final int minutes;
  const Experience(
    this.id,
    this.title,
    this.area,
    this.category,
    this.description,
    this.story,
    this.surprise,
    this.photo,
    this.minutes,
  );
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
  );
  String get imageUrl =>
      'https://images.unsplash.com/$photo?auto=format&fit=crop&w=1000&q=85';
}

class TransitLeg {
  final String mode, from, to, departure, arrival, transfer, walking, fare;
  const TransitLeg({
    required this.mode,
    required this.from,
    required this.to,
    required this.departure,
    required this.arrival,
    required this.transfer,
    required this.walking,
    required this.fare,
  });
}
