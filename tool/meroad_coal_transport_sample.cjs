'use strict';
// Independent schema-v1 input sample. No optimized itinerary is written.
const fs = require('node:fs');
const { buildPayload } = require('../functions/transport_optimizer');
const SAPPORO = 'jr_hokkaido~SlJfQUYwNzEzMjM4Qg';
const SHIN = 'jr_hokkaido~SlJfN0Q4QjI2RDEzNA';
const BUS = 'yutetsu_bus~UzAxODEwMDAxNzcwMDEwMA';
const MUSEUM = 'yutetsu_bus~UzAxODEwMDAyMDIwMDEwMA';
const railNames = new Set(['札幌', '苗穂', '白石', '平和', '新札幌', '上野幌', '北広島', '島松', '恵み野', '恵庭', 'サッポロビール庭園', '長都', '千歳', '南千歳', '追分', '川端', '新夕張']);
const sources = ['https://www.city.yubari.lg.jp/site/kanko/1197.html', 'https://www.coal-yubari.jp/info/', 'https://coal-yubari.jp/file/timetable202505n.pdf'];
function generate(network, records) {
  const melon = records.find((r) => r.id === 'melon'), coal = records.find((r) => r.id === 'coal');
  if (!melon || !coal) throw Error('Registered sightseeing records are missing');
  const station = network.stops.get(SAPPORO);
  const access = (stopId, walkingMinutes) => ({ stopId, walkingMinutes, sourceType: 'manual', verificationStatus: 'verified' });
  const endpoint = { id: '札幌駅', name: '札幌駅（JR乗車・降車地点）', latitude: station.latitude, longitude: station.longitude, accessStops: [access(SAPPORO, 0)] };
  const query = { date: '2026-11-01', departureSeconds: 30600, deadlineSeconds: 61200,
    origin: endpoint, destination: endpoint,
    visits: [{ id: melon.id, name: melon.name, latitude: melon.latitude, longitude: melon.longitude,
      staySeconds: melon.minutes * 60, opening: { status: 'known', windows: [[36000, 64800]] },
      accessStops: [access(SHIN, 5), access(BUS, 3)] },
    { id: coal.id, name: '夕張市石炭博物館', latitude: coal.latitude, longitude: coal.longitude,
      staySeconds: coal.minutes * 60, opening: { status: 'known', windows: [[36000, 57600]] },
      accessStops: [access(MUSEUM, 10)] }],
    modes: ['rail', 'bus', 'walk'], preference: 'transfers', minimumTransferSeconds: 300 };
  const allowedStops = new Set([...network.stops.values()].filter((s) =>
    (s.id.startsWith('jr_hokkaido~') && railNames.has(s.name)) || s.id.startsWith('yutetsu_bus~')).map((s) => s.id));
  const trips = network.trips.filter((t) =>
    (t.feedId === 'jr_hokkaido' && t.times.some((s) => allowedStops.has(s[0]))) ||
    (t.feedId === 'yutetsu_bus' && t.times.some((s) => [BUS, MUSEUM].includes(s[0]))));
  const versions = Object.fromEntries(trips.map((t) => [t.feedId, t.versionId]));
  // Build actual adjacent edges first; never join time rows after filtering stops.
  const { payload } = buildPayload({ ...network, trips }, query, { maxBytes: 5000000, versions });
  payload.segments = payload.segments.filter((s) => allowedStops.has(s.fromStopId) && allowedStops.has(s.toStopId));
  const instanceIds = new Set(payload.segments.map((s) => s.instanceId));
  payload.instances = payload.instances.filter((i) => instanceIds.has(i.id));
  const routeIds = new Set(payload.instances.map((i) => i.routeId));
  payload.routes = payload.routes.filter((r) => routeIds.has(r.id));
  const agencyIds = new Set(payload.routes.map((r) => r.agencyId));
  payload.agencies = payload.agencies.filter((a) => agencyIds.has(a.id));
  const stopIds = new Set(payload.segments.flatMap((s) => [s.fromStopId, s.toStopId]));
  for (const p of payload.places) for (const a of p.accessStops) stopIds.add(a.stopId);
  payload.stops = payload.stops.filter((s) => stopIds.has(s.id));
  const normalized = payload.transfers;
  payload.transfers = [...network.rules].flatMap(([pair, rules]) => {
    const [fromStopId, toStopId] = pair.split('\n');
    if (!stopIds.has(fromStopId) || !stopIds.has(toStopId)) return [];
    return rules.map((r) => {
      const { createdAt, updatedAt, ...data } = r;
      return { ...data, ...normalized.find((n) => n.id === r.id && n.fromStopId === fromStopId && n.toStopId === toStopId), fromStopId, toStopId };
    });
  });
  payload.warnings.push('営業時間・地点徒歩の確認はサンプル内の補完。本番登録の確認状態は更新していません。',
    '石炭博物館バス停から本館は公式案内で約500m。登録済み1分を使わず片道10分の計画余裕を採用。',
    '札幌駅はJR乗降地点。対象地域は札幌〜新夕張のJR17駅と新夕張・博物館に接続する夕鉄バス。範囲外を経由する経路は対象外。');
  const json = JSON.stringify(payload), bytes = Buffer.byteLength(json);
  if (bytes + 1 > 500000) throw Error(`Scoped JSON exceeds 500000 bytes: ${bytes}; no candidate truncation`);
  return { query, payload, json, report: { date: query.date, departure: '08:30', deadline: '17:00', bytes,
    stops: payload.stops.length, routes: payload.routes.length, agencies: payload.agencies.length,
    instances: payload.instances.length, segments: payload.segments.length, transfers: payload.transfers.length,
    versions, sources, inputOnly: true, openingOverrides: 'Official operating dates and hours for 2026-11-01; museum closed from 2026-11-04',
    walkingOverrides: 'Station endpoints 0; Meroad to JR 5min/bus 3min; museum bus stop to building 10min for official approx.500m; registered museum 1min is not used',
    scope: 'JR Sapporo–Shin-Yubari corridor (17 named stations), Yutetsu trips touching Shin-Yubari or museum. Filter only original adjacent edges, never bridge excluded stops. All scheduled alternatives in scope and time window retained.' } };
}
async function main() {
  let db;
  try {
    let network, records;
    const index = process.argv.indexOf('--snapshot');
    if (index >= 0) {
      const d = JSON.parse(fs.readFileSync(process.argv[index + 1], 'utf8'));
      network = { ...d, ...Object.fromEntries(['stops', 'routes', 'services', 'agencies'].map((k) => [k, new Map(d[k].map((r) => [r.id, r]))])), rules: new Map(d.rules) };
      records = JSON.parse(fs.readFileSync(process.argv[index + 2], 'utf8'));
    } else {
      const context = require('../functions/production_transport_context.cjs').context();
      db = context.db;
      network = await require('../functions/transport_optimizer_api').loadOptimizerNetwork(db, context.bucket);
      records = await Promise.all(['melon', 'coal'].map(async (id) => { const d = await db.collection('sightseeing_spot').doc(id).get(); return { ...d.data(), id: d.id }; }));
    }
    const sample = generate(network, records), prefix = 'docs/transport_optimizer_meroad_coal';
    fs.writeFileSync(`${prefix}_network.json`, `${sample.json}\n`);
    fs.writeFileSync(`${prefix}_request.json`, `${JSON.stringify(sample.query, null, 2)}\n`);
    fs.writeFileSync(`${prefix}_extraction.json`, `${JSON.stringify(sample.report, null, 2)}\n`);
    console.log(JSON.stringify(sample.report));
  } finally { if (db) await db.terminate(); }
}
if (require.main === module) main().catch((e) => { console.error(e.message); process.exitCode = 1; });
module.exports = { generate };
