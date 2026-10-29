import 'package:flutter/services.dart';
import '../model/experience.dart';
import '../model/mock_catalog.dart';

/// Replacing this repository is the boundary for a future Firestore catalog.
abstract interface class MockCatalogRepository {
  Future<MockCatalog> load();
}

class MarkdownMockCatalogRepository implements MockCatalogRepository {
  static const spotsDirectory = 'assets/mock_data/sightseeing_spot/';
  static const transitDirectory = 'assets/mock_data/transit/';
  final AssetBundle bundle;
  MarkdownMockCatalogRepository({AssetBundle? bundle})
    : bundle = bundle ?? rootBundle;

  @override
  Future<MockCatalog> load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    return loadFiles(manifest.listAssets());
  }

  /// Uses the same parser with explicit filenames in repository tests.
  Future<MockCatalog> loadFiles(Iterable<String> paths) async {
    final filenames =
        paths
            .where(
              (path) =>
                  path.endsWith('.md') &&
                  (path.startsWith(spotsDirectory) ||
                      path.startsWith(transitDirectory)),
            )
            .toSet()
            .toList()
          ..sort();
    final documents = await Future.wait(
      filenames.map(
        (path) async =>
            MarkdownRecord.parse(path, await bundle.loadString(path)),
      ),
    );
    final spots = documents
        .where((doc) => doc.path.startsWith(spotsDirectory))
        .toList();
    final transit = documents
        .where((doc) => doc.path.startsWith(transitDirectory))
        .toList();
    for (final group in [spots, transit]) {
      final ids = <String>{};
      for (final document in group) {
        if (!ids.add(document.required('id'))) document.fail('id が重複しています');
      }
      group.sort((a, b) {
        final order = a
            .integer('order', fallback: 1000)
            .compareTo(b.integer('order', fallback: 1000));
        return order != 0 ? order : a.path.compareTo(b.path);
      });
    }
    return MockCatalog(
      experiences: [for (final doc in spots) doc.toExperience()],
      transit: [for (final doc in transit) doc.toTransit()],
    );
  }
}

/// A deliberately small Markdown schema: title, metadata bullets, H2 sections.
class MarkdownRecord {
  final String path, title;
  final Map<String, String> metadata, sections;
  MarkdownRecord._(this.path, this.title, this.metadata, this.sections);
  factory MarkdownRecord.parse(String path, String source) {
    var title = '', section = '';
    final metadata = <String, String>{}, sections = <String, String>{};
    for (final line in source.replaceAll('\r\n', '\n').split('\n')) {
      if (line.startsWith('# ')) {
        if (title.isNotEmpty) throw FormatException('$path: タイトルは1つだけ指定してください');
        title = line.substring(2).trim();
      } else if (line.startsWith('## ')) {
        section = line.substring(3).trim();
        if (sections.containsKey(section)) {
          throw FormatException('$path: 見出し「$section」が重複しています');
        }
        sections[section] = '';
      } else if (section.isNotEmpty) {
        sections[section] = '${sections[section]}$line\n';
      } else if (line.startsWith('- ')) {
        final match = RegExp(r'^- ([a-z_]+):\s*(.*)$').firstMatch(line);
        if (match == null) {
          throw FormatException('$path: 基本情報は「- key: 値」で指定してください');
        }
        final key = match[1]!;
        if (metadata.containsKey(key)) {
          throw FormatException('$path: $key が重複しています');
        }
        metadata[key] = match[2]!.trim();
      } else if (line.trim().isNotEmpty) {
        throw FormatException('$path: 本文は「## 見出し」の下に書いてください');
      }
    }
    if (title.isEmpty) throw FormatException('$path: # タイトル が必要です');
    return MarkdownRecord._(path, title, metadata, {
      for (final entry in sections.entries) entry.key: entry.value.trim(),
    });
  }

  Never fail(String message) => throw FormatException('$path: $message');
  String required(String key) {
    final value = metadata[key];
    if (value == null || value.isEmpty) fail('$key を指定してください');
    return value;
  }

  int integer(String key, {int? fallback}) {
    final raw = metadata[key];
    if (raw == null && fallback != null) return fallback;
    final value = int.tryParse(raw ?? '');
    if (value == null || value < 0) fail('$key は0以上の整数で指定してください');
    return value;
  }

  String section(String name) {
    final value = sections[name];
    if (value == null || value.isEmpty) fail('## $name を記入してください');
    return value;
  }

  List<String> photos(String sectionName) => [
    for (final match in RegExp(
      r'!\[[^\]]*\]\(([^\n)]+)\)',
    ).allMatches(sections[sectionName] ?? ''))
      _imagePath(match[1]!.trim()),
  ];
  String _imagePath(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) fail('写真のパスが不正です');
    if (uri.scheme == 'http' || uri.scheme == 'https') return value;
    if (uri.hasScheme || value.startsWith('/')) {
      fail('写真は相対パス・assets/パス・https URLで指定してください');
    }
    final resolved = value.startsWith('assets/')
        ? uri
        : Uri.parse(path).resolveUri(uri);
    if (!resolved.path.startsWith('assets/')) fail('写真はassetsフォルダ内で指定してください');
    return Uri.decodeComponent(resolved.path);
  }

  Experience toExperience() => Experience(
    required('id'),
    title,
    required('area'),
    required('category'),
    section('紹介'),
    section('ストーリー'),
    section('意外な魅力'),
    photos('写真').firstOrNull ?? '',
    integer('minutes'),
    additionalPhotos: List.unmodifiable(photos('補足写真')),
    accessMinutes: integer('access_minutes', fallback: 120),
  );
  TransitSample toTransit() {
    final position = required('position');
    if (!['first', 'following', 'any'].contains(position)) {
      fail('position はfirst/following/anyで指定してください');
    }
    final departure = _minutes('departure');
    final arrival = _minutes('arrival');
    return TransitSample(
      id: required('id'),
      position: position,
      spotId: required('spot_id'),
      mode: required('mode'),
      transfer: required('transfer'),
      walking: required('walking'),
      fare: required('fare'),
      departureMinutes: departure,
      arrivalMinutes: arrival < departure ? arrival + 1440 : arrival,
      stepMinutes: integer('step_minutes', fallback: 0),
      photo: photos('写真').firstOrNull ?? '',
      note: section('注意'),
    );
  }

  int _minutes(String key) {
    final value = required(key);
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) fail('$key はHH:mm形式で指定してください');
    final hour = int.parse(match[1]!), minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) fail('$key の時刻が不正です');
    return hour * 60 + minute;
  }
}
