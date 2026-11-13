'use strict';
const { HttpsError } = require('firebase-functions/v2/https');
const { createHash } = require('node:crypto');
const { validDate } = require('./transport_router');
const { serialize } = require('./transport_payload_optimizer');
const { transportLimits } = require('./transport_limits');
const ENDPOINT = 'https://api.dify.ai/v1/workflows/run';
const invalid = () => { throw new HttpsError('invalid-argument', 'transport_dataにはschemaVersion: 1の交通ネットワークJSON文字列を指定してください。'); };
const object = (v) => v != null && typeof v === 'object' && !Array.isArray(v);
const id = (v) => typeof v === 'string' && v.length > 0 && v.length <= 1400;
const seconds = (v) => Number.isSafeInteger(v) && v >= 0;
function validateTransportData(data) {
  if (!object(data) || Object.keys(data).some((k) => k !== 'transport_data') || typeof data.transport_data !== 'string') invalid();
  // Check before parsing as well as after compact serialization. No silently truncated input.
  const raw = data.transport_data, limits = transportLimits();
  const rawBytes = Buffer.byteLength(raw);
  if (rawBytes > limits.maxBytes) throw new HttpsError('resource-exhausted', '交通データが送信容量を超えています。AIは実行していません。', { reason: 'transport-payload-too-large', difyRequestStarted: false, bytes: rawBytes, ...limits });
  let p;
  try { p = JSON.parse(raw); } catch { invalid(); }
  if (!object(p) || p.schemaVersion !== 1 || !validDate(p.date) || p.timezone !== 'Asia/Tokyo' ||
      !seconds(p.departureSeconds) || p.departureSeconds >= 86400 || !seconds(p.deadlineSeconds) ||
      p.deadlineSeconds <= p.departureSeconds || p.deadlineSeconds > 259200 ||
      !object(p.policy) || !['travel_time', 'transfers', 'walking'].includes(p.preference) ||
      !Array.isArray(p.modes) || !p.modes.length || p.modes.some((m) => !['rail', 'bus', 'walk'].includes(m))) invalid();
  for (const k of ['places', 'stops', 'routes', 'agencies', 'instances', 'segments', 'transfers']) if (!Array.isArray(p[k])) invalid();
  if (p.minimumTransferSeconds != null && (!Number.isInteger(p.minimumTransferSeconds) || p.minimumTransferSeconds < 180 || p.minimumTransferSeconds > 3600)) invalid();
  const index = (rows) => {
    const result = new Map();
    for (const r of rows) { if (!object(r) || !id(r.id) || result.has(r.id)) invalid(); result.set(r.id, r); }
    return result;
  };
  const stops = index(p.stops), agencies = index(p.agencies), routes = index(p.routes), instances = index(p.instances);
  for (const r of routes.values()) if (!id(r.agencyId) || !agencies.has(r.agencyId)) invalid();
  for (const i of instances.values()) if (!id(i.tripId) || !routes.has(i.routeId) || !validDate(i.serviceDate) || typeof i.verificationStatus !== 'string') invalid();
  if (p.places.length < 3 || p.places.length > 5 || p.places.filter((v) => v?.role === 'origin').length !== 1 || p.places.filter((v) => v?.role === 'destination').length !== 1) invalid();
  const visits = new Set();
  for (const v of p.places) {
    if (!object(v) || !id(v.id) || typeof v.name !== 'string' || !['origin', 'visit', 'destination'].includes(v.role) || !Array.isArray(v.accessStops) || v.accessStops.length > 30) invalid();
    for (const a of v.accessStops) if (!object(a) || !stops.has(a.stopId) || (a.seconds != null && !seconds(a.seconds)) || typeof a.usableForRouting !== 'boolean' || typeof a.estimated !== 'boolean') invalid();
    if (v.role === 'visit') {
      if (visits.has(v.id) || !seconds(v.staySeconds) || !v.staySeconds || !object(v.opening) || !['known', 'closed', 'unknown'].includes(v.opening.status) || !Array.isArray(v.opening.windows)) invalid();
      visits.add(v.id);
      if ((v.opening.status === 'known') !== (v.opening.windows.length > 0)) invalid();
      for (const w of v.opening.windows) if (!Array.isArray(w) || w.length !== 2 || !w.every(seconds) || w[1] <= w[0]) invalid();
    }
  }
  if (visits.size < 1 || visits.size > 3) invalid();
  for (const s of p.segments) if (!object(s) || !instances.has(s.instanceId) || !stops.has(s.fromStopId) || !stops.has(s.toStopId) ||
    !Number.isSafeInteger(s.fromSequence) || !Number.isSafeInteger(s.toSequence) || s.fromSequence < 0 || s.toSequence <= s.fromSequence ||
    !seconds(s.departureSeconds) || !seconds(s.arrivalSeconds) || s.arrivalSeconds < s.departureSeconds || s.departureSeconds < p.departureSeconds || s.arrivalSeconds > p.deadlineSeconds ||
    typeof s.pickup !== 'boolean' || typeof s.dropoff !== 'boolean') invalid();
  for (const t of p.transfers) if (!object(t) || !stops.has(t.fromStopId) || !stops.has(t.toStopId) || !Number.isInteger(t.transferType) || t.transferType < 0 || t.transferType > 5 ||
    (t.minTransferSeconds != null && !seconds(t.minTransferSeconds))) invalid();
  try { return serialize(p, limits); } catch (e) {
    throw new HttpsError(e.code === 'resource-exhausted' ? 'resource-exhausted' : 'invalid-argument', '交通データが送信上限を超えています。AIは実行していません。', e.details);
  }
}
async function limitTransportRequests(db, uid, now = Date.now()) {
  const key = createHash('sha256').update(uid).digest('hex');
  const ref = db.collection('_transport_optimizer_request_limits').doc(key);
  await db.runTransaction(async (tx) => {
    const previous = (await tx.get(ref)).data() || {};
    const active = Number.isFinite(previous.startedAt) && now >= previous.startedAt && now - previous.startedAt < 60000;
    const count = active && Number.isSafeInteger(previous.count) ? previous.count : 0;
    if (count >= 3) throw new HttpsError('resource-exhausted', '短時間にAIを実行できる回数を超えました。時間をおいてお試しください。', { reason: 'ai-minute-limit', difyRequestStarted: false, limit: 3, retryAfterSeconds: Math.max(1, Math.ceil((previous.startedAt + 60000 - now) / 1000)) });
    tx.set(ref, { startedAt: active ? previous.startedAt : now, count: count + 1 });
  });
}
async function readBoundedResponse(response, signal) {
  const reader = response.body?.getReader();
  if (!reader) throw new HttpsError('internal', '交通最適化の応答形式が不正です。');
  const chunks = []; let size = 0;
  try {
    while (true) {
      signal.throwIfAborted();
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 1000000) { await reader.cancel(); throw new HttpsError('internal', '交通最適化の応答サイズが上限を超えました。'); }
      chunks.push(Buffer.from(value));
    }
  } finally { reader.releaseLock(); }
  return Buffer.concat(chunks).toString('utf8');
}
function parseItinerary(json) {
  if (json?.data?.status !== 'succeeded') throw new HttpsError('internal', '交通最適化Workflowが正常に完了しませんでした。');
  const o = json.data.outputs;
  if (!object(o)) throw new HttpsError('internal', '交通最適化の出力形式が不正です。');
  const flags = ['success', 'recommendation'].filter((k) => Object.hasOwn(o, k));
  if (!flags.length || flags.some((k) => typeof o[k] !== 'boolean') || (flags.length === 2 && o.success !== o.recommendation) || typeof o.itinerary_json !== 'string')
    throw new HttpsError('internal', '交通最適化の成功フラグまたは旅程形式が不正です。');
  let itinerary;
  try { itinerary = JSON.parse(o.itinerary_json); } catch { throw new HttpsError('internal', '旅程JSONを解析できませんでした。'); }
  if (!object(itinerary) || typeof itinerary.status !== 'string' || !itinerary.status.trim()) throw new HttpsError('internal', '旅程JSONの構造が不正です。');
  const success = o[flags[0]];
  // Do not echo the upstream message, which can contain inputs or internal errors.
  return { success, itinerary, message: success ? '旅程生成成功' : '旅程を生成できませんでした' };
}
async function optimizeTransportItinerary(request, db, getApiKey, options = {}) {
  if (typeof request.auth?.uid !== 'string' || !request.auth.uid) throw new HttpsError('unauthenticated', 'ログインが必要です。');
  const input = validateTransportData(request.data);
  let apiKey;
  try { apiKey = getApiKey(); } catch { throw new HttpsError('failed-precondition', '交通最適化の接続設定を確認してください。'); }
  if (typeof apiKey !== 'string' || !apiKey.trim()) throw new HttpsError('failed-precondition', '交通最適化の接続設定を確認してください。');
  try { await limitTransportRequests(db, request.auth.uid, options.now?.() ?? Date.now()); }
  catch (e) { if (e instanceof HttpsError) throw e; throw new HttpsError('unavailable', '呼出し制限の確認に失敗しました。'); }
  // Confirmed against published GET /parameters: transport_data is json_object.
  // Keep the Flutter/Callable JSON-string contract; convert only at the Dify boundary.
  const inputType = process.env.DIFY_TRANSPORT_INPUT_TYPE ?? 'json_object';
  if (!['json_object', 'string'].includes(inputType)) throw new HttpsError('failed-precondition', '交通最適化の入力型設定を確認してください。');
  const transportData = inputType === 'json_object' ? input.payload : input.json;
  const signal = AbortSignal.timeout(options.timeoutMs ?? 90000);
  try {
    await options.onDispatch?.();
    const response = await (options.fetch ?? fetch)(ENDPOINT, {
      method: 'POST', redirect: 'error',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ inputs: { transport_data: transportData }, response_mode: 'blocking', user: createHash('sha256').update(request.auth.uid).digest('hex') }), signal,
    });
    if (!response.ok) {
      // Never read or expose HTTP error bodies.
      if (response.status === 429) throw new HttpsError('resource-exhausted', 'AIサービスが混み合っているか利用上限に達しています。結果の確認が必要です。', { reason: 'dify-rate-limit', httpStatus: response.status, difyRequestStarted: true });
      if ([401, 403].includes(response.status)) throw new HttpsError('failed-precondition', '交通最適化の接続設定を確認してください。', { reason: 'dify-auth-error', httpStatus: response.status, difyRequestStarted: true });
      throw new HttpsError('unavailable', '交通最適化サービスがリクエストを受け付けませんでした。', { reason: 'dify-http-error', httpStatus: response.status, difyRequestStarted: true });
    }
    const raw = await readBoundedResponse(response, signal);
    if (raw.includes(apiKey)) throw new HttpsError('internal', '交通最適化の応答を受け取れませんでした。');
    let json;
    try { json = JSON.parse(raw); } catch { throw new HttpsError('internal', '交通最適化の応答を解析できませんでした。'); }
    if (JSON.stringify(json).includes(apiKey)) throw new HttpsError('internal', '交通最適化の応答を受け取れませんでした。');
    await options.onWorkflowResponse?.(json);
    return parseItinerary(json);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    if (signal.aborted || ['AbortError', 'TimeoutError'].includes(e?.name)) throw new HttpsError('deadline-exceeded', '交通最適化がタイムアウトしました。自動再試行は行いません。');
    throw new HttpsError('unavailable', '交通最適化との通信に失敗しました。');
  }
}
module.exports = { optimizeTransportItinerary, validateTransportData, parseItinerary, limitTransportRequests };
