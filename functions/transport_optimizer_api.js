"use strict";
const { HttpsError } = require('firebase-functions/v2/https');
const { gunzipSync } = require('node:zlib');
const { createHash } = require('node:crypto');
const { loadNetwork, allRows } = require('./transport_journey_api');
const { validateInput, buildPayload, normalizePlaces, PreparationError } = require('./transport_optimizer');
const { serialize, metrics, deduplicate, connectedNetwork, pruneUnreachable, TransportPayloadCache, cacheKey } = require('./transport_payload_optimizer');
const { transportLimits } = require('./transport_limits');
const { measureFirestore } = require('./transport_read_metrics');
const payloadCache = new TransportPayloadCache();
let cache;
const hash = (b) => createHash('sha256').update(b).digest('hex');
async function readVerified(bucket, path, descriptor, compressed) {
  const limit = compressed ? 4 * 1024 * 1024 : 2 * 1024 * 1024;
  if (!descriptor || !Number.isInteger(descriptor.bytes) || descriptor.bytes <= 0 || descriptor.bytes > limit || !/^[a-f0-9]{64}$/.test(descriptor.checksum)) throw new PreparationError('failed-precondition', 'カタログ管理情報が不正です');
  const [bytes] = await bucket.file(path).download({ validation: 'crc32c' });
  if (bytes.length !== descriptor.bytes || hash(bytes) !== descriptor.checksum) throw new PreparationError('data-loss', 'カタログ検証に失敗しました');
  const raw = compressed ? gunzipSync(bytes, { maxOutputLength: limit }) : bytes;
  if (compressed && raw.length !== descriptor.rawBytes) throw new PreparationError('data-loss', 'カタログ容量が一致しません');
  return JSON.parse(raw);
}
async function loadOptimizerNetwork(db, bucket) {
  const loaded = await loadNetwork(db, bucket);
  // An incomplete feed set must never masquerade as an exhaustive optimization input.
  if (loaded.warnings.length) throw new PreparationError('failed-precondition', loaded.warnings.join(' / '));
  if (cache?.key === loaded.key) return cache.network;
  const routes = new Map(), agencies = new Map();
  const current = loaded.activeFeeds.map((f) => ({ id: f.id, data: () => f }));
  for (const doc of current) {
    const f = doc.data(), prefix = `transport_data/${doc.id}/${f.activeVersionId}`;
    if (loaded.versions[doc.id] !== f.activeVersionId || f.distribution?.manifestPath !== `${prefix}/manifest.json`) throw new PreparationError('aborted', '公開版が更新されたか管理情報が不正です');
    const manifest = await readVerified(bucket, `${prefix}/manifest.json`, { bytes: f.distribution.manifestBytes, checksum: f.distribution.manifestChecksum }, false);
    if (manifest.feedId !== doc.id || manifest.versionId !== f.activeVersionId) throw new PreparationError('data-loss', 'マニフェストの版が一致しません');
    const catalog = await readVerified(bucket, `${prefix}/catalog.json.gz`, manifest.assets['catalog.json.gz'], true);
    for (const r of catalog.routes) routes.set(r.id, r);
    for (const a of catalog.agencies) agencies.set(a.id, a);
  }
  for (const [collection, target] of [['transport_routes', routes], ['transport_agencies', agencies]]) {
    for (const r of (collection === 'transport_routes' ? loaded.manualRecords.routes : await allRows(db, collection))) if (r.isActive !== false && r.sourceType !== 'sample' && r.verificationStatus !== 'sample') target.set(r.id, r);
  }
  const network = { ...loaded.network, routes, agencies, optimizerVersionKey: loaded.key };
  cache = { key: loaded.key, network };
  return network;
}
async function prepareTransportOptimization(request, db, bucket, options = {}) {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', '認証が必要です');
  try {
    validateInput(request.data);
    const started = Date.now();
    const measured = measureFirestore(db);
    const network = await (options.loadNetwork ?? loadOptimizerNetwork)(measured.db, bucket);
    // Keep every potentially usable path. No geographic or top-N limits are applied.
    // Default-on: otherwise unrelated feeds can exceed capacity before Dify is called.
    const pruning = process.env.TRANSPORT_OPTIMIZER_PRUNE !== 'false';
    const key = cacheKey(network.optimizerVersionKey, request.data, pruning);
    let common = payloadCache.get(key);
    const cacheHit = common != null;
    if (!common) {
      const extractionNetwork = pruning ? connectedNetwork(network, request.data) : network;
      const raw = buildPayload(extractionNetwork, request.data, {
        maxBytes: 32 * 1024 * 1024,
        versions: Object.fromEntries(network.trips.filter((t) => t.feedId && t.versionId).map((t) => [t.feedId, t.versionId])),
      });
      const optimized = pruning ? pruneUnreachable(raw.payload, { includeVisits: true }) : deduplicate(raw.payload);
      // Keep user names, coordinates and opening hours out of the shared cache.
      const { places, preference, ...transport } = optimized;
      common = { transport, before: metrics(raw.json), beforePlaces: metrics(JSON.stringify(raw.payload.places)), beforePreference: metrics(JSON.stringify(raw.payload.preference)) };
      payloadCache.set(key, common);
    }
    const currentPlaces = normalizePlaces(network, request.data);
    const currentPlaceSize = metrics(JSON.stringify(currentPlaces));
    const currentPreferenceSize = metrics(JSON.stringify(request.data.preference));
    const before = Object.fromEntries(Object.keys(common.before).map((k) => [k, common.before[k] - common.beforePlaces[k] - common.beforePreference[k] + currentPlaceSize[k] + currentPreferenceSize[k]]));
    const result = serialize({ ...common.transport,
      preference: request.data.preference, places: currentPlaces }, transportLimits());
    const stats = { ...measured.stats, payloadCacheHit: cacheHit, pruning,
      before, after: { characters: result.characters, utf16Units: result.utf16Units, bytes: result.bytes },
      generationMs: Date.now() - started, difySendMs: null };
    // Aggregate measurements only. Never log locations, query contents or credentials.
    console.info('transportOptimizationPreparation', stats);
    return { workflow: 'TABISAKI_Transport_Optimizer', inputs: { transport_json: result.json },
      bytes: result.bytes, characters: result.characters, stats };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    if (e instanceof PreparationError) {
      if (e.details) console.info('transportOptimizationSizeRejected', e.details);
      throw new HttpsError(e.code, e.message, e.details ?? (e.code === 'resource-exhausted' ? { reason: 'transport-build-limit', difyRequestStarted: false } : undefined));
    }
    throw new HttpsError('internal', '交通データの生成に失敗しました');
  }
}
module.exports = { prepareTransportOptimization, loadOptimizerNetwork };
