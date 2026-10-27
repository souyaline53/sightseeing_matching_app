enum TravelMode { transit, car, either }

enum TripLength { halfDay, day, overnight, longer }

enum DateChoice { tomorrow, weekend, fixed }

enum Walking { light, normal, plenty }

enum Company { solo, friends, couple, family }

extension TravelModeLabel on TravelMode {
  String get label => ['公共交通', '車', 'どちらでも'][index];
}

extension TripLengthLabel on TripLength {
  String get label => ['半日', '日帰り', '1泊2日', '2泊3日以上'][index];
}

extension WalkingLabel on Walking {
  String get label => ['少なめ', '普通', 'たくさん歩ける'][index];
}

extension CompanyLabel on Company {
  String get label => ['一人旅', '友人', 'カップル', '家族旅行'][index];
}

T _enum<T>(List<T> values, Object? index, T fallback) =>
    index is int && index >= 0 && index < values.length
    ? values[index]
    : fallback;
int _amount(Object? value, int fallback, int min, int max) =>
    value is num ? value.toInt().clamp(min, max) : fallback;

class SearchConditions {
  final String origin;
  final TravelMode transport;
  final TripLength length;
  final DateChoice dateChoice;
  final DateTime? fixedDate;
  final int budget, maxMinutes;
  final Walking walking;
  final Company company;
  const SearchConditions({
    this.origin = '札幌駅',
    this.transport = TravelMode.transit,
    this.length = TripLength.day,
    this.dateChoice = DateChoice.tomorrow,
    this.fixedDate,
    this.budget = 10000,
    this.maxMinutes = 120,
    this.walking = Walking.normal,
    this.company = Company.solo,
  });
  DateTime resolveDate([DateTime? now]) {
    final time = now ?? DateTime.now();
    final today = DateTime(time.year, time.month, time.day);
    return switch (dateChoice) {
      DateChoice.tomorrow => DateTime(today.year, today.month, today.day + 1),
      DateChoice.weekend => DateTime(
        today.year,
        today.month,
        today.day + ((DateTime.saturday - today.weekday + 7) % 7),
      ),
      DateChoice.fixed => fixedDate ?? today,
    };
  }

  String? validate([DateTime? now]) {
    if (origin.trim().isEmpty) return '出発地を入力してください。';
    final time = now ?? DateTime.now();
    final today = DateTime(time.year, time.month, time.day);
    if (dateChoice == DateChoice.fixed &&
        (fixedDate == null || resolveDate(time).isBefore(today))) {
      return '過去の日付は使えません。旅行日を選び直してください。';
    }
    return null;
  }

  String get summary =>
      '$origin · ${transport.label} · ${length.label} · 総予算$budget円';
  SearchConditions copyWith({
    String? origin,
    TravelMode? transport,
    TripLength? length,
    DateChoice? dateChoice,
    DateTime? fixedDate,
    int? budget,
    int? maxMinutes,
    Walking? walking,
    Company? company,
  }) => SearchConditions(
    origin: origin ?? this.origin,
    transport: transport ?? this.transport,
    length: length ?? this.length,
    dateChoice: dateChoice ?? this.dateChoice,
    fixedDate: fixedDate ?? this.fixedDate,
    budget: budget ?? this.budget,
    maxMinutes: maxMinutes ?? this.maxMinutes,
    walking: walking ?? this.walking,
    company: company ?? this.company,
  );
  Map<String, dynamic> toJson() => {
    'origin': origin,
    'transport': transport.index,
    'length': length.index,
    'dateChoice': dateChoice.index,
    'fixedDate': fixedDate?.toIso8601String(),
    'budget': budget,
    'maxMinutes': maxMinutes,
    'walking': walking.index,
    'company': company.index,
  };
  factory SearchConditions.fromJson(Map<String, dynamic> json) =>
      SearchConditions(
        origin: json['origin'] as String? ?? '札幌駅',
        transport: _enum(
          TravelMode.values,
          json['transport'],
          TravelMode.transit,
        ),
        length: _enum(TripLength.values, json['length'], TripLength.day),
        dateChoice: _enum(
          DateChoice.values,
          json['dateChoice'],
          DateChoice.tomorrow,
        ),
        fixedDate: DateTime.tryParse(json['fixedDate'] as String? ?? ''),
        budget: _amount(json['budget'], 10000, 1000, 100000),
        maxMinutes: _amount(json['maxMinutes'], 120, 30, 300),
        walking: _enum(Walking.values, json['walking'], Walking.normal),
        company: _enum(Company.values, json['company'], Company.solo),
      );
}

class UserProfile {
  final String origin;
  final TravelMode transport;
  final int budget;
  final Walking walking;
  const UserProfile({
    this.origin = '札幌駅',
    this.transport = TravelMode.transit,
    this.budget = 10000,
    this.walking = Walking.normal,
  });
  SearchConditions defaults() => SearchConditions(
    origin: origin,
    transport: transport,
    budget: budget,
    walking: walking,
  );
  Map<String, dynamic> toJson() => {
    'origin': origin,
    'transport': transport.index,
    'budget': budget,
    'walking': walking.index,
  };
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final c = SearchConditions.fromJson(json);
    return UserProfile(
      origin: c.origin,
      transport: c.transport,
      budget: c.budget,
      walking: c.walking,
    );
  }
}

class SearchPreset {
  final String id, name;
  final SearchConditions conditions;
  const SearchPreset({
    required this.id,
    required this.name,
    required this.conditions,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'conditions': conditions.toJson(),
  };
  factory SearchPreset.fromJson(Map<String, dynamic> json) => SearchPreset(
    id: json['id'] as String,
    name: json['name'] as String,
    conditions: SearchConditions.fromJson(
      json['conditions'] as Map<String, dynamic>,
    ),
  );
}

class LastSearch {
  final SearchConditions conditions;
  final DateTime executedAt;
  const LastSearch({required this.conditions, required this.executedAt});
  Map<String, dynamic> toJson() => {
    'conditions': conditions.toJson(),
    'executedAt': executedAt.toIso8601String(),
  };
  factory LastSearch.fromJson(Map<String, dynamic> json) => LastSearch(
    conditions: SearchConditions.fromJson(
      json['conditions'] as Map<String, dynamic>,
    ),
    executedAt: DateTime.parse(json['executedAt'] as String),
  );
}

class SavedSettings {
  final UserProfile profile;
  final List<SearchPreset> presets;
  final LastSearch? lastSearch;
  SavedSettings({
    this.profile = const UserProfile(),
    List<SearchPreset> presets = const [],
    this.lastSearch,
  }) : presets = List.unmodifiable(presets);
  SavedSettings copyWith({
    UserProfile? profile,
    List<SearchPreset>? presets,
    LastSearch? lastSearch,
  }) => SavedSettings(
    profile: profile ?? this.profile,
    presets: presets ?? this.presets,
    lastSearch: lastSearch ?? this.lastSearch,
  );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'profile': profile.toJson(),
    'presets': presets.map((e) => e.toJson()).toList(),
    'lastSearch': lastSearch?.toJson(),
  };
  factory SavedSettings.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported settings version');
    }
    return SavedSettings(
      profile: UserProfile.fromJson(json['profile'] as Map<String, dynamic>),
      presets: (json['presets'] as List)
          .map((e) => SearchPreset.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastSearch: json['lastSearch'] == null
          ? null
          : LastSearch.fromJson(json['lastSearch'] as Map<String, dynamic>),
    );
  }
}
