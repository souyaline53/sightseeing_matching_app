"use strict";
const { HttpsError } = require("firebase-functions/v2/https");
const { gunzipSync, gzipSync } = require("node:zlib");
const { createHash } = require("node:crypto");
const { routingData } = require("./transport_routing_bundle");
const { validateQuery, prepareNetwork, searchJourneys } = require("./transport_router");
const hash = (b) => createHash("sha256").update(b).digest("hex");
let cached = null, pending = null;
async function allRows(db, collection) {
  const rows = [];
  let cursor;
  while (true) {
    let q = db.collection(collection).orderBy("__name__").limit(200);
    if (cursor) q = q.startAfter(cursor);
    const page = await q.get();
    for (const d of page.docs) rows.push({ ...d.data(), id: d.id });
    if (rows.length > 20000) throw new HttpsError("resource-exhausted", "手動マスターが検索上限を超えています");
    if (page.size < 200) break;
    cursor = page.docs.at(-1);
  }
  return rows;
}
async function loadNetwork(db, bucket) {
  // Small metadata only per search. Assets/manual tables are retained across warm calls.
  const [feeds, revision] = await Promise.all([db.collection("transport_feeds").limit(101).get(), db.doc("transport_routing_state/manual").get()]);
  if (feeds.size > 100) throw new HttpsError("resource-exhausted", "フィード数が検索上限を超えています");
  const active = feeds.docs.map((d) => ({ ...d.data(), id: d.id })).filter((f) => f.activeVersionId);
  const key = JSON.stringify([active.map((f) => [f.id, f.activeVersionId, f.distribution?.routing?.checksum]), revision.data()?.revision || "initial"]);
  if (cached?.key === key) return cached;
  if (pending?.key === key) return pending.promise;
  const promise = (async () => {
    const parts = [], warnings = [], versions = {};
    let storageBytes = 0, rawBytes = 0;
    for (const feed of active) {
      const descriptor = feed.distribution?.routing;
      if (!descriptor) { warnings.push(`${feed.id}: 乗換検索用データが未作成です`); continue; }
      const prefix = `transport_data/${feed.id}/${feed.activeVersionId}/routing-`;
      rawBytes += descriptor.rawBytes || 0;
      if (descriptor.path !== `${prefix}${descriptor.checksum}.json.gz` || !/^[a-f0-9]{64}$/.test(descriptor.checksum) || !Number.isInteger(descriptor.bytes) || descriptor.bytes <= 0 || descriptor.bytes > 32 * 1024 * 1024 || !Number.isInteger(descriptor.rawBytes) || descriptor.rawBytes <= 0 || rawBytes > 128 * 1024 * 1024)
        throw new HttpsError("failed-precondition", "検索用データの管理情報が不正です");
      const [bytes] = await bucket.file(descriptor.path).download();
      if (hash(bytes) !== descriptor.checksum || bytes.length !== descriptor.bytes) throw new HttpsError("data-loss", "検索用データの検証に失敗しました");
      const raw = gunzipSync(bytes, { maxOutputLength: 128 * 1024 * 1024 });
      if (raw.length !== descriptor.rawBytes) throw new HttpsError("data-loss", "検索用データの容量不一致");
      const data = JSON.parse(raw);
      if (data.feedId !== feed.id || data.versionId !== feed.activeVersionId || ![1, 2].includes(data.formatVersion)) throw new HttpsError("data-loss", "検索用データの版不一致");
      if (data.timezone !== "Asia/Tokyo") { warnings.push(`${feed.id}: 日本標準時以外のフィードは未対応です`); continue; }
      if (data.formatVersion === 1) warnings.push(`${feed.id}: 500m停留所グループのデータ更新待ちです`);
      parts.push(data); versions[feed.id] = feed.activeVersionId; storageBytes += bytes.length;
    }
    const manual = {};
    for (const [kind, collection] of Object.entries({ stops: "transport_stops", routes: "transport_routes", services: "transport_services", trips: "transport_trips", transfers: "transport_transfers" }))
      manual[kind] = (await allRows(db, collection)).filter((r) => r.isActive !== false && r.sourceType !== "sample" && r.verificationStatus !== "sample");
    parts.push(routingData(manual, revision.data()?.revision || "initial"));
    return cached = { key, network: prepareNetwork(parts), warnings, versions, storageBytes, activeFeeds: active, manualRecords: manual, results: new Map() };
  })();
  pending = { key, promise };
  try { return await promise; } finally { if (pending?.promise === promise) pending = null; }
}
async function searchTransportJourneys(request, db, bucket) {
  let query;
  try { query = validateQuery(request.data); } catch (e) { throw new HttpsError("invalid-argument", e.message); }
  const loaded = await loadNetwork(db, bucket);
  const start = Date.now();
  const queryKey = JSON.stringify(query);
  let base = loaded.results.get(queryKey);
  const cacheHit = !!base;
  if (!base) {
    base = searchJourneys(loaded.network, query);
    loaded.results.set(queryKey, base);
    if (loaded.results.size > 32) loaded.results.delete(loaded.results.keys().next().value);
  }
  const result = { ...base, warnings: [...base.warnings], stats: { ...base.stats } };
  if (!result.walkingOnly) result.warnings.push(...loaded.warnings, "区間運賃・乗継割引は未確認です。検索範囲は出発から48時間以内です。");
  result.versions = loaded.versions;
  result.stats.elapsedMs = Date.now() - start;
  result.stats.cacheHit = cacheHit;
  // Aggregate metrics only: do not log a user's location or itinerary.
  console.info("transportJourneySearch", { ...result.stats, resultCount: result.journeys.length, cachedNetworkBytes: loaded.storageBytes });
  if (query.timetable) {
    const raw = Buffer.from(JSON.stringify(result.journeys));
    const journeyPool = { encoding: "gzip+base64", rawBytes: raw.length, data: gzipSync(raw).toString("base64") };
    delete result.journeys;
    return { ...result, journeyPool };
  }
  return result;
}
module.exports = { searchTransportJourneys, loadNetwork, allRows };
