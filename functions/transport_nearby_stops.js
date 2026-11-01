"use strict";
const EARTH_METERS = 6371000;
const MAX_SAME_NAME_METERS = 500;
const MAX_TRANSFERS = 3;
const radians = (value) => value * Math.PI / 180;
function coordinates(stop) {
  const latitude = stop.latitude ?? stop.location?.latitude;
  const longitude = stop.longitude ?? stop.location?.longitude;
  return Number.isFinite(latitude) && Math.abs(latitude) <= 90 &&
    Number.isFinite(longitude) && Math.abs(longitude) <= 180
    ? { latitude, longitude } : null;
}
function normalizedStopName(name) {
  return typeof name === "string" ? name.normalize("NFC").trim() : "";
}
function distanceMeters(a, b) {
  const x = coordinates(a), y = coordinates(b);
  if (!x || !y) return null;
  const dLat = radians(y.latitude - x.latitude), dLon = radians(y.longitude - x.longitude);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(radians(x.latitude)) *
    Math.cos(radians(y.latitude)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_METERS * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}
function estimatedWalkingSeconds(distance) {
  // An estimate, not a walking route: 60m/min, 1.3x detour, plus 2 minutes.
  return Math.max(180, Math.ceil((distance * 1.3 / 60 + 2)) * 60);
}
function buildSameNameConnections(stops, includePair = () => true) {
  const names = new Map(), connections = [];
  for (const stop of stops) {
    const name = normalizedStopName(stop.name), point = coordinates(stop);
    if (!name || !point || stop.isActive === false || ![0, 4].includes(stop.locationType ?? 0)) continue;
    if (!names.has(name)) names.set(name, []);
    names.get(name).push({ ...stop, ...point });
  }
  const latitudeWindow = MAX_SAME_NAME_METERS / EARTH_METERS * 180 / Math.PI;
  for (const rows of names.values()) {
    rows.sort((a, b) => a.latitude - b.latitude || a.id.localeCompare(b.id));
    for (let i = 0; i < rows.length; i++) {
      for (let j = i + 1; j < rows.length && rows[j].latitude - rows[i].latitude <= latitudeWindow + 1e-12; j++) {
        const a = rows[i], b = rows[j];
        if (a.id === b.id || !includePair(a, b)) continue;
        const distance = distanceMeters(a, b);
        if (distance <= MAX_SAME_NAME_METERS + 1e-8)
          connections.push([a.id, b.id, Math.round(distance), estimatedWalkingSeconds(distance)]);
      }
    }
  }
  // These are direct pairs, not transitive connected components: A-B-C must not join A-C >500m.
  return connections;
}
module.exports = { MAX_TRANSFERS, MAX_SAME_NAME_METERS, coordinates, normalizedStopName, distanceMeters, estimatedWalkingSeconds, buildSameNameConnections };
