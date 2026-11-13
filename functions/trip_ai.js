'use strict';
const { randomUUID, createHash } = require('node:crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const { optimizeTransportItinerary, validateTransportData } = require('./transport_dify');
const { prepareTransportOptimization } = require('./transport_optimizer_api');
const validId = (v) => typeof v === 'string' && /^[A-Za-z0-9_-]{1,150}$/.test(v);
function user(request) {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'ログインが必要です。');
  return request.auth.uid;
}
function plan(value) {
  if (!value || !validId(value.id) || !Array.isArray(value.stops) || !Array.isArray(value.saved) || Buffer.byteLength(JSON.stringify(value)) > 180000)
    throw new HttpsError('invalid-argument', '旅程データを確認してください。');
  return value;
}
const doc = (db, uid, id) => db.doc(`users/${uid}/ai_trips/${id}`);
async function registerAiTrip(request, db) {
  const uid = user(request), trip = plan(request.data?.trip);
  const lineage = trip.ai?.lineage ?? trip.id;
  if (!validId(lineage)) throw new HttpsError('invalid-argument', '旅の識別子が不正です。');
  const alias = db.doc(`_ai_trip_aliases/${createHash('sha256').update(`${uid}/${lineage}`).digest('hex')}`);
  const id = randomUUID();
  return db.runTransaction(async (tx) => {
    const previous = await tx.get(alias);
    const root = previous.data()?.rootId || request.data?.rootId;
    if (root) {
      if (!validId(root)) throw new HttpsError('invalid-argument', '旅程IDが不正です。');
      const snap = await tx.get(doc(db, uid, root));
      if (!snap.exists || snap.data().ownerUid !== uid) throw new HttpsError('permission-denied', '旅程を操作できません。');
      const data = snap.data();
      const recoverable = data.aiGenerationStatus === 'processing' && data.aiGenerationPhase === 'reserved' && Date.now() - data.aiGenerationStartedAt >= 600000;
      if (recoverable) tx.update(doc(db, uid, root), { aiGenerationStatus: 'failed', aiGenerationPhase: 'expired_before_dispatch' });
      if (!previous.exists) tx.set(alias, { rootId: root, ownerUid: uid });
      return { tripId: root, aiGenerationStatus: recoverable ? 'failed' : data.aiGenerationStatus };
    }
    tx.create(doc(db, uid, id), { ownerUid: uid, aiGenerationStatus: 'unused', currentTrip: JSON.stringify(trip), createdAt: Date.now() });
    tx.set(alias, { rootId: id, ownerUid: uid });
    return { tripId: id, aiGenerationStatus: 'unused' };
  });
}
async function optimizeTripTransport(request, db, bucket, getApiKey, options = {}) {
  const uid = user(request), { tripId, requestId } = request.data || {};
  if (!validId(tripId) || !validId(requestId)) throw new HttpsError('invalid-argument', '旅程IDとリクエストIDが必要です。');
  const ref = doc(db, uid, tripId);
  const initial = await ref.get();
  if (!initial.exists || initial.data().ownerUid !== uid) throw new HttpsError('permission-denied', '旅程を操作できません。');
  if (initial.data().aiGenerationStatus === 'completed') return JSON.parse(initial.data().aiResult);
  if (initial.data().aiGenerationStatus === 'uncertain' || (initial.data().aiGenerationStatus === 'processing' && (initial.data().aiGenerationPhase !== 'reserved' || Date.now() - initial.data().aiGenerationStartedAt < 600000))) throw new HttpsError('already-exists', '処理中または結果確認待ちです。保存済み結果を確認してください。');
  // Generate using the existing GTFS builder when the UI sends input conditions.
  let transport = request.data.transport_data;
  if (!transport) {
    const prepared = await (options.prepare ?? prepareTransportOptimization)({ ...request, data: request.data.input }, db, bucket);
    transport = prepared.inputs.transport_json;
  }
  const network = JSON.parse(validateTransportData({ transport_data: transport }).json);
  const visits = network.places.filter((p) => p.role === 'visit').map((p) => p.id).sort();
  const savedIds = JSON.parse(initial.data().currentTrip).stops.map((s) => s.id).sort();
  if (JSON.stringify(visits) !== JSON.stringify(savedIds)) throw new HttpsError('failed-precondition', '訪問先が変わりました。旅程を保存して再実行してください。');
  // Availability/readability is checked before reserving. Never expose a Secret value.
  let key;
  try { key = getApiKey(); } catch { throw new HttpsError('failed-precondition', '交通最適化の接続設定を確認してください。'); }
  if (!key) throw new HttpsError('failed-precondition', '交通最適化の接続設定を確認してください。');
  const leaseId = randomUUID();
  const usageRef = db.doc(`_ai_trip_daily_limits/${createHash('sha256').update(uid).digest('hex')}-${new Date().toISOString().slice(0, 10)}`);
  const reservation = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref), data = snap.data();
    if (!data || data.ownerUid !== uid) throw new HttpsError('permission-denied', '旅程を操作できません。');
    if (data.aiGenerationStatus === 'completed') return JSON.parse(data.aiResult);
    if (data.aiGenerationStatus === 'uncertain' || (data.aiGenerationStatus === 'processing' && (data.aiGenerationPhase !== 'reserved' || Date.now() - data.aiGenerationStartedAt < 600000))) throw new HttpsError('already-exists', '処理中または結果確認待ちです。再送信せず保存済み結果を確認してください。');
    if (JSON.stringify(JSON.parse(data.currentTrip).stops.map((s) => s.id).sort()) !== JSON.stringify(visits)) throw new HttpsError('aborted', '訪問先が変わりました。');
    const usage = (await tx.get(usageRef)).data()?.count ?? 0;
    if (usage >= 10) throw new HttpsError('resource-exhausted', '本日のAI作成回数の上限に達しました。', { reason: 'ai-daily-limit', difyRequestStarted: false, limit: 10, resetAt: new Date((Math.floor(Date.now() / 86400000) + 1) * 86400000).toISOString() });
    tx.set(usageRef, { count: usage + 1 });
    tx.update(ref, { aiGenerationStatus: 'processing', aiGenerationRequestId: requestId, aiLeaseId: leaseId, aiGenerationPhase: 'reserved', aiGenerationStartedAt: Date.now() });
    return null;
  });
  if (reservation) return reservation;
  let dispatched = false, definitiveFailure = false;
  try {
    const result = await (options.run ?? optimizeTransportItinerary)(
      { ...request, data: { transport_data: transport } }, db, () => key,
      { ...options, onDispatch: async () => {
        await db.runTransaction(async (tx) => {
          const data = (await tx.get(ref)).data();
          if (data.aiLeaseId !== leaseId || data.aiGenerationPhase !== 'reserved') throw new HttpsError('aborted', '要求の予約が変わりました。');
          tx.update(ref, { aiGenerationPhase: 'dispatched', aiDifyCallCount: (data.aiDifyCallCount ?? 0) + 1 });
        });
        dispatched = true;
        console.info('aiTripGeneration', { outcome: 'dispatched', tripId, requestId });
      }, onWorkflowResponse: async (json) => {
        definitiveFailure = ['failed', 'stopped'].includes(json?.data?.status);
        const runId = json?.workflow_run_id ?? json?.data?.id;
        if (typeof runId === 'string' && runId.length < 200) await ref.update({ aiWorkflowRunId: runId });
      } },
    );
    if (Buffer.byteLength(JSON.stringify(result)) > 180000) throw new HttpsError('internal', '保存できる旅程サイズを超えています。');
    if (!result.success || result.itinerary?.status === 'infeasible') {
      await ref.update({ aiGenerationStatus: 'failed', aiGenerationPhase: 'finished', aiLastErrorCode: 'workflow-failed' });
      return { ...result, success: false };
    }
    const itinerary = result.itinerary;
    const assumptions = network.places.flatMap(p => [
      ...(p.opening?.status === 'unknown' || p.opening?.assumedOpen ? [`営業時間未確認（営業している前提）: ${p.name}`] : []),
      ...(p.accessStops.some(a => a.requiresReview) ? [`登録済み徒歩接続の確認が必要: ${p.name}`] : []),
    ]);
    if (assumptions.length) { itinerary.requiresReview = true; itinerary.reviewReasons = [...(Array.isArray(itinerary.reviewReasons) ? itinerary.reviewReasons : []), ...assumptions]; }
    if (!['feasible', 'needs_review'].includes(itinerary?.status)) throw new HttpsError('internal', '旅程の状態を確認できません。');
    const order = itinerary.visitOrder ?? itinerary.visits?.map((v) => v.spotId ?? v.placeId ?? v.id);
    if (!Array.isArray(order) || JSON.stringify([...order].sort()) !== JSON.stringify(visits)) throw new HttpsError('internal', 'AIの訪問順序を確認できません。');
    const lookup = {};
    // Only referenced labels, never the input network, are persisted.
    const encoded = JSON.stringify(itinerary);
    for (const kind of ['stops', 'routes']) lookup[kind] = network[kind].filter((r) => encoded.includes(r.id));
    const agencyIds = new Set(lookup.routes.map((r) => r.agencyId));
    lookup.agencies = network.agencies.filter((a) => agencyIds.has(a.id) || encoded.includes(a.id));
    await db.runTransaction(async (tx) => {
      const current = (await tx.get(ref)).data();
      if (current.aiLeaseId !== leaseId) throw new HttpsError('aborted', '要求の状態が変わりました。');
      result.aiMetadata = { visitOrder: order, lookup, input: { date: network.date, departureSeconds: network.departureSeconds, deadlineSeconds: network.deadlineSeconds, places: network.places, modes: network.modes } };
      if (Buffer.byteLength(JSON.stringify(result)) > 180000) throw new HttpsError('internal', '旅程の保存容量を超えています。');
      tx.update(ref, { aiGenerationStatus: 'completed', aiGenerationPhase: 'finished', aiGeneratedAt: Date.now(),
        aiResult: JSON.stringify(result), aiVisitOrder: order, aiDisplayLookup: lookup, aiInput: JSON.stringify({
          date: network.date, departureSeconds: network.departureSeconds, deadlineSeconds: network.deadlineSeconds,
          places: network.places, modes: network.modes,
        }) });
    });
    console.info('aiTripGeneration', { outcome: 'completed', tripId, requestId });
    return result;
  } catch (e) {
    // Never expire/retry a dispatched operation: the upstream may already have charged.
    try { await db.runTransaction(async (tx) => { const data = (await tx.get(ref)).data(); if (data.aiLeaseId === leaseId && data.aiGenerationStatus !== 'completed') tx.update(ref, { aiGenerationStatus: dispatched && !definitiveFailure ? 'uncertain' : 'failed', aiLastErrorCode: e instanceof HttpsError ? e.code : 'unavailable' }); }); } catch (_) { /* original durable processing reservation remains locked */ }
    console.info('aiTripGeneration', {
      outcome: dispatched && !definitiveFailure ? 'uncertain' : 'failed', tripId, requestId,
      errorCode: e instanceof HttpsError ? e.code : 'unavailable',
      ...(Number.isInteger(e.details?.httpStatus) ? { httpStatus: e.details.httpStatus } : {}),
    });
    if (e instanceof HttpsError) throw e;
    throw new HttpsError('unavailable', '旅程の生成結果を確認できません。保存状態を確認してください。');
  }
}
module.exports = { registerAiTrip, optimizeTripTransport };
