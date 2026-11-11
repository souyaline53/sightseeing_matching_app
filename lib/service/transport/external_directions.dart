import 'package:flutter/foundation.dart';
import '../../model/experience.dart';

enum DirectionsMode { walking, transit, driving }

/// Both endpoints are required so a missing location never becomes current location.
Uri? externalDirectionsUri(
  Experience from,
  Experience to, {
  required DirectionsMode mode,
  required TargetPlatform platform,
  bool web = false,
}) {
  String? endpoint(Experience place) {
    final address = place.address.trim();
    if (address.isNotEmpty) {
      return [
        place.displayName.trim(),
        address,
      ].where((part) => part.isNotEmpty).join(' ');
    }
    // Departure points and older records may only have coordinates.
    final lat = place.latitude, lon = place.longitude;
    if (lat == null ||
        lon == null ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180) {
      return null;
    }
    return '$lat,$lon';
  }

  final origin = endpoint(from), destination = endpoint(to);
  if (origin == null || destination == null) return null;
  if (!web && platform == TargetPlatform.iOS) {
    return Uri.https('maps.apple.com', '/', {
      'saddr': origin,
      'daddr': destination,
      'dirflg': switch (mode) {
        DirectionsMode.walking => 'w',
        DirectionsMode.transit => 'r',
        DirectionsMode.driving => 'd',
      },
    });
  }
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'origin': origin,
    'destination': destination,
    'travelmode': mode.name,
  });
}
