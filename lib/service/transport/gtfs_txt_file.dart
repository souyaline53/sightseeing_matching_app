import 'dart:typed_data';

class GtfsTxtFile {
  final String name;
  final Uint8List bytes;
  const GtfsTxtFile(this.name, this.bytes);
}

const gtfsFileDescriptions = {
  'agency.txt': '必須：交通事業者',
  'stops.txt': '必須：駅・バス停',
  'routes.txt': '必須：路線',
  'trips.txt': '必須：便・運行日との対応',
  'stop_times.txt': '必須：停車順・到着／出発時刻',
  'calendar.txt': 'calendar_dates.txtと少なくとも一方：曜日・運行期間',
  'calendar_dates.txt': 'calendar.txtと少なくとも一方：運行日・例外日',
  'fare_attributes.txt': '任意：片道運賃',
  'fare_rules.txt': '任意：運賃の適用区間',
  'feed_info.txt': '任意／translations.txt使用時必須：配信元・有効期間',
  'agency_jp.txt': '任意：日本向け事業者情報',
  'routes_jp.txt': '任意：日本向け路線情報（原本保存）',
  'office_jp.txt': '任意：営業所（原本保存）',
  'translations.txt': '任意：翻訳（原本保存）',
  'pass_attributes.txt': '任意：定期券・フリーパス',
  'pass_rules.txt': '任意：パス適用区間',
  'shapes.txt': '任意：経路形状（原本保存）',
  'transfers.txt': '任意：乗換（原本保存）',
  'frequencies.txt': '任意：頻度運行（対象便は通常の時刻表検索対象外）',
};
