'use strict';
// Read-only production extraction, or offline: --snapshot /path/to/network.json
// Run from repository root. Writes local documentation samples only.
const fs = require('node:fs');
const { buildPayload } = require('../functions/transport_optimizer');
const SAPPORO = 'jr_hokkaido~SlJfQUYwNzEzMjM4Qg';
const SHIN_YUBARI = 'jr_hokkaido~SlJfN0Q4QjI2RDEzNA';
const sourceUrl = 'https://www.city.yubari.lg.jp/site/kanko/1197.html';
function generate(network) {
  const station = network.stops.get(SAPPORO);
  const endpoint = { id: '札幌駅', name: '札幌駅（JR乗車・降車地点）',
    latitude: station.latitude, longitude: station.longitude,
    accessStops: [{ stopId: SAPPORO, walkingMinutes: 0, sourceType: 'manual', verificationStatus: 'verified' }] };
  const query = { date: '2026-11-13', departureSeconds: 37800, deadlineSeconds: 52200,
    origin: endpoint, destination: endpoint,
    visits: [{ id: 'melon', name: '道の駅メロード', latitude: 42.93531, longitude: 142.035492,
      staySeconds: 3600, opening: { status: 'known', windows: [[36000, 64800]] },
      accessStops: [{ stopId: SHIN_YUBARI, walkingMinutes: 5, sourceType: 'manual',
        verificationStatus: 'verified', sourceUrl }] }],
    modes: ['rail', 'walk'], preference: 'transfers', minimumTransferSeconds: 300 };
  query.modes = ['rail', 'bus', 'walk'];
  // Region is defined by station connectivity, not a geographic clipping of stop times.
  // Every retained trip keeps all intermediate stops, including those outside this corridor.
  const corridorNames = new Set(['札幌', '新札幌', '南千歳', '追分', '新夕張']);
  const anchors = new Set([...network.stops.values()].filter((s) =>
    s.id.startsWith('jr_hokkaido~') && corridorNames.has(s.name)).map((s) => s.id));
  const busStop = 'yutetsu_bus~UzAxODEwMDAxNzcwMDEwMA';
  const scopedTrips = network.trips.filter((t) =>
    (t.feedId === 'jr_hokkaido' && t.times.some((s) => anchors.has(s[0]))) ||
    (t.feedId === 'yutetsu_bus' && t.times.some((s) => s[0] === busStop)));
  // Preserve registered bus access without upgrading its unverified status.
  query.visits[0].accessStops.push({ stopId: busStop, walkingMinutes: 3,
    sourceType: 'manual', verificationStatus: 'unverified' });
  const scoped = { ...network, trips: scopedTrips };
  const versions = Object.fromEntries(scopedTrips.filter((t) => t.feedId && t.versionId).map((t) => [t.feedId, t.versionId]));
  const built = buildPayload(scoped, query, { versions });
  // Keep every transfer rule for retained stops, even if the Code node cannot yet implement it.
  // Administrative timestamps alone are omitted. No rule is filtered by usableForRouting.
  const stopIds = new Set(built.payload.stops.map((s) => s.id));
  built.payload.transfers = [...network.rules].flatMap(([pair, rules]) => {
    const [fromStopId, toStopId] = pair.split('\n');
    if (!stopIds.has(fromStopId) || !stopIds.has(toStopId)) return [];
    return rules.map((rule) => {
      const { createdAt, updatedAt, ...data } = rule;
      const normalized = built.payload.transfers.find((r) => r.id === rule.id &&
        r.fromStopId === fromStopId && r.toStopId === toStopId);
      return { ...data, ...normalized, fromStopId, toStopId };
    });
  });
  const json = JSON.stringify(built.payload);
  const bytes = Buffer.byteLength(json);
  if (bytes > 500000) throw Error(`Network JSON too large: ${bytes} bytes; no truncation performed`);
  return { query, payload: built.payload, json, report: {
    date: query.date, bytes, stops: built.payload.stops.length, routes: built.payload.routes.length,
    agencies: built.payload.agencies.length, instances: built.payload.instances.length,
    segments: built.payload.segments.length, transfers: built.payload.transfers.length,
    scope: 'JR trips touching Sapporo/Shin-Sapporo/Minami-Chitose/Oiwake/Shin-Yubari and Yutetsu trips touching Shin-Yubari station bus stop; all intermediate stops retained',
    versions,
  } };
}

async function main() {
  let network, db;
  const index = process.argv.indexOf('--snapshot');
  try {
    if (index >= 0) {
      const d = JSON.parse(fs.readFileSync(process.argv[index + 1], 'utf8'));
      network = { ...d, ...Object.fromEntries(['stops', 'routes', 'services', 'agencies'].map((k) => [k, new Map(d[k].map((r) => [r.id, r]))])), rules: new Map(d.rules) };
    } else {
      const context = require('../functions/production_transport_context.cjs').context();
      db = context.db;
      network = await require('../functions/transport_optimizer_api').loadOptimizerNetwork(db, context.bucket);
    }
    const sample = generate(network);
    fs.writeFileSync('docs/transport_optimizer_meroad_request.json', `${JSON.stringify(sample.query, null, 2)}\n`);
    // Compact form is directly suitable for the Dify string input, under the actual byte cap.
    fs.writeFileSync('docs/transport_optimizer_sample.json', `${sample.json}\n`);
    fs.writeFileSync('docs/transport_optimizer_meroad_extraction.json', `${JSON.stringify(sample.report, null, 2)}\n`);
    console.log(JSON.stringify(sample.report));
  } finally { if (db) await db.terminate(); }
}
if (require.main === module) main().catch((e) => { console.error(e.message); process.exitCode = 1; });
module.exports = { generate };
