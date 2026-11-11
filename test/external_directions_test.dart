import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sightseeing_matching_app/model/experience.dart';
import 'package:sightseeing_matching_app/service/transport/external_directions.dart';

Experience place(
  double? lat,
  double? lon, {
  String name = '',
  String address = '',
}) => Experience(
  'id',
  'place',
  '',
  '',
  '',
  '',
  '',
  '',
  0,
  latitude: lat,
  longitude: lon,
  name: name,
  address: address,
);

void main() {
  test('facility names and addresses distinguish identical coordinates', () {
    final from = place(
      43,
      141,
      name: ' 道の駅 夕張メロード ',
      address: ' 北海道夕張市紅葉山526-19 ',
    );
    final to = place(43, 141, name: '栗下食堂', address: '北海道夕張市紅葉山526-6');
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      for (final web in [false, true]) {
        final uri = externalDirectionsUri(
          from,
          to,
          mode: DirectionsMode.walking,
          platform: platform,
          web: web,
        )!;
        final apple = platform == TargetPlatform.iOS && !web;
        final params = Uri.parse(uri.toString()).queryParameters;
        expect(
          params[apple ? 'saddr' : 'origin'],
          '道の駅 夕張メロード 北海道夕張市紅葉山526-19',
        );
        expect(params[apple ? 'daddr' : 'destination'], '栗下食堂 北海道夕張市紅葉山526-6');
      }
    }
  });
  test('address works without coordinates and falls back to display title', () {
    final uri = externalDirectionsUri(
      place(43, 141, address: '  '),
      place(null, null, address: '北海道夕張市紅葉山526-6'),
      mode: DirectionsMode.driving,
      platform: TargetPlatform.android,
    )!;
    expect(uri.queryParameters['origin'], '43.0,141.0');
    expect(uri.queryParameters['destination'], 'place 北海道夕張市紅葉山526-6');
  });
  test('iOS passes both coordinates and transit mode to Apple Maps', () {
    final uri = externalDirectionsUri(
      place(43, 141),
      place(44, 142),
      mode: DirectionsMode.transit,
      platform: TargetPlatform.iOS,
    )!;
    expect(uri.host, 'maps.apple.com');
    expect(uri.queryParameters, {
      'saddr': '43.0,141.0',
      'daddr': '44.0,142.0',
      'dirflg': 'r',
    });
  });
  test('Android and web preserve endpoints and each travel mode', () {
    for (final mode in DirectionsMode.values) {
      for (final web in [false, true]) {
        final uri = externalDirectionsUri(
          place(43, 141),
          place(44, 142),
          mode: mode,
          platform: web ? TargetPlatform.iOS : TargetPlatform.android,
          web: web,
        )!;
        expect(uri.host, 'www.google.com');
        expect(uri.queryParameters['origin'], '43.0,141.0');
        expect(uri.queryParameters['destination'], '44.0,142.0');
        expect(uri.queryParameters['travelmode'], mode.name);
      }
    }
  });
  test('missing or invalid coordinates never launch a different route', () {
    for (final invalid in [
      place(null, 141),
      place(43, null),
      place(double.nan, 141),
      place(91, 141),
      place(43, 181),
    ]) {
      for (final pair in [
        [invalid, place(44, 142)],
        [place(44, 142), invalid],
      ]) {
        expect(
          externalDirectionsUri(
            pair[0],
            pair[1],
            mode: DirectionsMode.driving,
            platform: TargetPlatform.android,
          ),
          isNull,
        );
      }
    }
  });
}
