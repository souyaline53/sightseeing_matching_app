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
