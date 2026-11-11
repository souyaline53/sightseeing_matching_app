"use strict";
// A server-only compact timetable. Existing immutable display manifests stay unchanged.
const { createHash } = require("node:crypto");
const { gzipSync } = require("node:zlib");
const { coordinates, buildSameNameConnections } = require("./transport_nearby_stops");
const digest = (b) => createHash("sha256").update(b).digest("hex");
function routingData(data, versionId) {
  const stops = data.stops.filter((s) => s.isActive !== false).map((s) => ({ id: s.id, name: s.name, ...coordinates(s), locationType: s.locationType ?? 0, platformCode: s.platformCode, parentStationId: s.parentStationId, zoneId: s.zoneId }));
  return {
    stops,
    sameNameConnections: buildSameNameConnections(stops),
    routes: data.routes.filter((r) => r.isActive !== false).map((r) => ({ id: r.id, name: r.name, feedId: r.feedId, trainType: r.trainType || null, requiresLimitedExpress: r.requiresLimitedExpress === true })),
    services: data.services,
    trips: data.trips.filter((t) => t.isActive !== false && !t.frequencyBased && t.sourceType !== "sample" && t.verificationStatus !== "sample").map((t) => ({
      id: t.id, routeId: t.routeId, serviceId: t.serviceId, headsign: t.headsign,
      versionId: t.versionId || versionId, feedId: t.feedId, verificationStatus: t.verificationStatus || "unverified", sourceType: t.sourceType || "manual",
      times: t.stopTimes.slice().sort((a, b) => a.sequence - b.sequence).map((s) => [s.stopId, s.sequence,
        s.arrivalSeconds ?? (s.arrivalMinutes == null ? null : s.arrivalMinutes * 60),
        s.departureSeconds ?? (s.departureMinutes == null ? null : s.departureMinutes * 60),
        s.pickupAllowed !== false && (s.pickupType == null || s.pickupType === 0),
        s.dropoffAllowed !== false && (s.dropOffType == null || s.dropOffType === 0)]),
    })),
    transfers: data.transfers || [],
  };
}
function buildRoutingBundle(parsed, feedId, versionId) {
  if (parsed.errors.length) throw Error("検証エラーがあるフィードは公開できません");
  const raw = Buffer.from(JSON.stringify({ formatVersion: 2, feedId, versionId, timezone: parsed.summary.timezone, ...routingData(parsed.data, versionId) }));
  const bytes = gzipSync(raw, { level: 6 }), checksum = digest(bytes);
  const path = `transport_data/${feedId}/${versionId}/routing-${checksum}.json.gz`;
  return { descriptor: { path, checksum, bytes: bytes.length, rawBytes: raw.length }, object: { path, bytes } };
}
module.exports = { routingData, buildRoutingBundle };
