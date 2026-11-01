"use strict";
const { createHash } = require("node:crypto");
const { gzipSync } = require("node:zlib");
// Display hints only. Stop IDs, service eligibility and boarding rules remain authoritative.
function buildStopLabels(parsed, feedId, versionId) {
  if (parsed.errors.length)
    throw Error("検証エラーのあるデータから乗り場案内は生成できません");
  const names = new Map(parsed.data.stops.map((s) => [s.id, s.name])),
    stops = {};
  for (const trip of parsed.data.trips) {
    const times = trip.stopTimes,
      origin = names.get(times[0]?.stopId),
      destination =
        (trip.headsign || "").trim() || names.get(times.at(-1)?.stopId);
    for (let i = 0; i < times.length; i++) {
      const s = times[i];
      const byRoute = (stops[s.stopId] ??= {});
      const label = (byRoute[trip.routeId] ??= {
        departures: new Set(),
        arrivals: new Set(),
      });
      if (i < times.length - 1 && s.pickupType === 0 && destination)
        label.departures.add(destination);
      if (i > 0 && s.dropOffType === 0 && origin) label.arrivals.add(origin);
    }
  }
  for (const byRoute of Object.values(stops))
    for (const value of Object.values(byRoute)) {
      value.departures = [...value.departures].sort();
      value.arrivals = [...value.arrivals].sort();
    }
  const raw = Buffer.from(JSON.stringify({ feedId, versionId, stops }));
  if (raw.length > 4 * 1024 * 1024) throw Error("乗り場案内の容量上限超過");
  const bytes = gzipSync(raw),
    checksum = createHash("sha256").update(bytes).digest("hex");
  const path = `transport_data/${feedId}/${versionId}/stop-labels-${checksum}.json.gz`;
  return {
    descriptor: { path, checksum, bytes: bytes.length, rawBytes: raw.length },
    object: { path, bytes },
  };
}
module.exports = { buildStopLabels };
