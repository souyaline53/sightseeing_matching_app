"use strict";
const { HttpsError } = require('firebase-functions/v2/https');
const { gunzipSync } = require('node:zlib');
const { createHash } = require('node:crypto');
const { loadNetwork, allRows } = require('./transport_journey_api');
const { validateInput, buildPayload, PreparationError } = require('./transport_optimizer');
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
  const feeds = await db.collection('transport_feeds').limit(101).get();
  if (feeds.size > 100) throw new PreparationError('resource-exhausted', 'フィード数が多すぎます');
  const current = feeds.docs.filter((d) => d.data().activeVersionId);
  if (current.length !== Object.keys(loaded.versions).length) throw new PreparationError('aborted', '公開版が更新されました。再実行してください');
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
    for (const r of await allRows(db, collection)) if (r.isActive !== false && r.sourceType !== 'sample' && r.verificationStatus !== 'sample') target.set(r.id, r);
  }
  const network = { ...loaded.network, routes, agencies };
  cache = { key: loaded.key, network };
  return network;
}
async function prepareTransportOptimization(request, db, bucket) {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', '認証が必要です');
  try {
    validateInput(request.data);
    const network = await loadOptimizerNetwork(db, bucket);
    const result = buildPayload(network, request.data, { versions: Object.fromEntries(network.trips.filter((t) => t.feedId && t.versionId).map((t) => [t.feedId, t.versionId])) });
    return { workflow: 'TABISAKI_Transport_Optimizer', inputs: { transport_json: result.json }, bytes: result.bytes };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    if (e instanceof PreparationError) throw new HttpsError(e.code, e.message);
    throw new HttpsError('internal', '交通データの生成に失敗しました');
  }
}
module.exports = { prepareTransportOptimization, loadOptimizerNetwork };
