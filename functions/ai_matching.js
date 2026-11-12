const { HttpsError } = require('firebase-functions/v2/https');
const { FieldPath } = require('firebase-admin/firestore');
const { randomInt, createHash } = require('node:crypto');
const CANDIDATE_LIMIT = 30;
const SPOT_FIELDS = ['name', 'title', 'area', 'category', 'description', 'story', 'surprise', 'minutes', 'openingHoursStatus', 'openingHours', 'specialHours', 'seasonalAvailability', 'recommendedSeasons', 'environmentType', 'admissionFee', 'reservationRequired', 'experienceTags', 'officialUrl', 'latitude', 'longitude', 'accessMinutes', 'accessNotes', 'accessStops'];
const text = (v, max = 2000) => typeof v === 'string' ? v.slice(0, max) : '';
const number = v => typeof v === 'number' && Number.isFinite(v) ? v : null;
const list = v => Array.isArray(v) ? v.slice(0, 100) : [];
const strings = v => list(v).filter(x => typeof x === 'string').map(x => text(x, 120));
const object = v => v && typeof v === 'object' && !Array.isArray(v) ? v : {};
const choice = (v, options) => options.includes(v) ? v : 'unknown';
const hours = v => list(v).map(h => ({open: text(h?.open, 5), close: text(h?.close, 5)}));
function serializeSpot(doc) {
  const d = doc.data();
  const season = object(d.seasonalAvailability), fee = object(d.admissionFee);
  return {
    id: doc.id,
    ...Object.fromEntries(['name', 'title', 'area', 'category', 'description', 'story', 'surprise', 'accessNotes', 'officialUrl'].map(k => [k, text(d[k])])),
    ...Object.fromEntries(['minutes', 'latitude', 'longitude', 'accessMinutes'].map(k => [k, number(d[k])])),
    openingHoursStatus: choice(d.openingHoursStatus, ['unknown', 'scheduled', 'always_open']),
    // Missing weekdays remain unknown (null), never silently converted to closed [].
    openingHours: d.openingHours && typeof d.openingHours === 'object' ? Object.fromEntries(['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].map(day => [day, Array.isArray(d.openingHours[day]) ? hours(d.openingHours[day]) : null])) : null,
    specialHours: list(d.specialHours).map(s => ({date: text(s?.date, 10), closed: typeof s?.closed === 'boolean' ? s.closed : null, hours: hours(s?.hours), note: text(s?.note, 500)})),
    seasonalAvailability: {status: choice(season.status, ['unknown', 'year_round', 'seasonal']), periods: list(season.periods).map(p => Object.fromEntries(['startMonth', 'startDay', 'endMonth', 'endDay'].map(k => [k, number(p?.[k])])) )},
    recommendedSeasons: strings(d.recommendedSeasons),
    environmentType: choice(d.environmentType, ['unknown', 'indoor', 'outdoor', 'mixed']),
    admissionFee: {status: choice(fee.status, ['unknown', 'free', 'paid', 'variable']), adultYen: number(fee.adultYen), childYen: number(fee.childYen), note: text(fee.note, 500)},
    reservationRequired: typeof d.reservationRequired === 'boolean' ? d.reservationRequired : null,
    experienceTags: strings(d.experienceTags),
    accessStops: list(d.accessStops).map(s => ({stopId: text(s?.stopId, 200), stopName: text(s?.stopName, 200), walkingMinutes: number(s?.walkingMinutes), walkingDistanceMeters: number(s?.walkingDistanceMeters), isPrimary: typeof s?.isPrimary === 'boolean' ? s.isPrimary : null, accessNotes: text(s?.accessNotes, 500)})),
  };
}
function requireUser(request) {
  if (!request.auth || typeof request.auth.uid !== 'string' || !request.auth.uid) throw new HttpsError('unauthenticated', 'ログインが必要です。');
}
function validateInput(data) {
  if (!data || ['interests', 'mood'].some(k => typeof data[k] !== 'string' || !data[k].trim() || data[k].length > 500)) throw new HttpsError('invalid-argument', '興味・気分を正しく入力してください。');
  let context;
  if (data.travelContext != null) {
    const raw = data.travelContext;
    if (!raw || typeof raw !== 'object' || Array.isArray(raw) || JSON.stringify(raw).length > 12000) throw new HttpsError('invalid-argument', '旅行条件の形式が正しくありません。');
    context = {};
    // Explicit whitelist: never forward arbitrary profile fields or account details.
    for (const key of ['origin', 'destination', 'visitArea', 'transport', 'tripLength', 'visitDate', 'visitDateTime', 'company', 'walking']) {
      if (raw[key] != null) {
        if (typeof raw[key] !== 'string' || raw[key].length > 200) throw new HttpsError('invalid-argument', '旅行条件の文字列が正しくありません。');
        context[key] = raw[key];
      }
    }
    for (const key of ['budgetYen', 'maxTravelMinutes', 'availableMinutes']) {
      if (raw[key] != null) {
        if (!Number.isSafeInteger(raw[key]) || raw[key] < 0 || raw[key] > 10000000) throw new HttpsError('invalid-argument', '旅行条件の数値が正しくありません。');
        context[key] = raw[key];
      }
    }
    if (raw.savedSpotIds != null) {
      if (!Array.isArray(raw.savedSpotIds) || raw.savedSpotIds.length > 100 || raw.savedSpotIds.some(id => typeof id !== 'string' || id.length > 200)) throw new HttpsError('invalid-argument', '保存済み観光地IDの形式が正しくありません。');
      context.savedSpotIds = [...new Set(raw.savedSpotIds)];
    }
    context.timeZone = 'Asia/Tokyo';
  }
  return {interests: data.interests.trim(), mood: context ? JSON.stringify({mood: data.mood.trim(), travelContext: context}) : data.mood.trim()};
}

// Random circular window, independent of interest, hours, fees or any ranking.
// Every ID can be selected. offset entails billed skipped reads; see docs for scale limits.
async function loadCandidates(db, chooseOffset = randomInt) {
  const collection = db.collection('sightseeing_spot');
  const total = (await collection.count().get()).data().count;
  if (!total) return [];
  const offset = total > CANDIDATE_LIMIT ? chooseOffset(total) : 0;
  const query = collection.orderBy(FieldPath.documentId()).select(...SPOT_FIELDS);
  const first = await query.offset(offset).limit(CANDIDATE_LIMIT).get();
  let docs = first.docs;
  if (offset && docs.length < Math.min(total, CANDIDATE_LIMIT)) {
    docs = [...docs, ...(await query.limit(Math.min(offset, CANDIDATE_LIMIT - docs.length)).get()).docs];
  }
  return [...new Map(docs.map(doc => [doc.id, doc])).values()].slice(0, CANDIDATE_LIMIT).map(serializeSpot);
}
async function rateLimit(db, uid, now = Date.now()) {
  const key = createHash('sha256').update(uid).digest('hex');
  const doc = db.collection('_ai_request_limits').doc(key);
  await db.runTransaction(async tx => {
    const previous = (await tx.get(doc)).data() ?? {};
    const active = typeof previous.startedAt === 'number' && now - previous.startedAt < 60000;
    const count = active ? previous.count : 0;
    if (count >= 6) throw new HttpsError('resource-exhausted', 'AI検索は1分に6回までです。少し待って再試行してください。');
    tx.set(doc, {startedAt: active ? previous.startedAt : now, count: count + 1});
  });
}
function parseRecommendations(json, spots) {
  if (json?.data?.status !== 'succeeded') throw new HttpsError('internal', 'AIの処理が正常に完了しませんでした。');
  let result = json.data.outputs?.recommendations;
  if (typeof result === 'string') {
    try { result = JSON.parse(result); } catch { throw new HttpsError('internal', 'AIの出力形式が正しくありません。'); }
  }
  if (!Array.isArray(result?.recommendations)) throw new HttpsError('internal', '推薦データの形式が正しくありません。');
  const ids = new Set(spots.map(s => s.id)), used = new Set(), recommendations = [];
  for (const item of result.recommendations) {
    if (!item || typeof item.spot_id !== 'string' || !ids.has(item.spot_id) || used.has(item.spot_id) || typeof item.reason !== 'string') continue;
    used.add(item.spot_id);
    recommendations.push({spot_id: item.spot_id, reason: item.reason.slice(0, 1000)});
    if (recommendations.length === 10) break;
  }
  if (result.recommendations.length && !recommendations.length) throw new HttpsError('internal', '有効な推薦結果がありません。再試行してください。');
  return recommendations;
}
async function getMatchingSpots(request, db) {
  requireUser(request);
  try {
    const spots = await loadCandidates(db);
    return {success: true, count: spots.length, spots};
  } catch { throw new HttpsError('unavailable', '観光地情報を取得できませんでした。'); }
}
async function readResponse(response) {
  const reader = response.body?.getReader();
  if (!reader) return '';
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 1000000) {
        await reader.cancel();
        throw new HttpsError('internal', 'AIの応答が大きすぎます。');
      }
      chunks.push(Buffer.from(value));
    }
  } finally { reader.releaseLock(); }
  return Buffer.concat(chunks).toString('utf8');
}
async function getAiRecommendations(request, db, apiKey, options = {}) {
  requireUser(request);
  const inputs = validateInput(request.data);
  if (!apiKey) throw new HttpsError('failed-precondition', 'AI接続が設定されていません。');
  let spots;
  try {
    await rateLimit(db, request.auth.uid);
    spots = await loadCandidates(db, options.chooseOffset);
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('unavailable', '観光地情報を取得できませんでした。');
  }
  if (!spots.length) return {recommendations: []};
  inputs.spots = JSON.stringify(spots);
  if (Buffer.byteLength(inputs.spots) > 500000) throw new HttpsError('resource-exhausted', '候補データが大きすぎます。管理者にお問い合わせください。');
  try {
    const response = await (options.fetch ?? fetch)('https://api.dify.ai/v1/workflows/run', {
      method: 'POST', headers: {Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json'},
      body: JSON.stringify({inputs, response_mode: 'blocking', user: createHash('sha256').update(request.auth.uid).digest('hex')}),
      signal: AbortSignal.timeout(options.timeoutMs ?? 55000),
    });
    if (!response.ok) throw new HttpsError('unavailable', 'AI推薦サービスに接続できませんでした。');
    const raw = await readResponse(response);
    let json;
    try { json = JSON.parse(raw); } catch { throw new HttpsError('internal', 'AIの出力形式が正しくありません。'); }
    return {recommendations: parseRecommendations(json, spots)};
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (['AbortError', 'TimeoutError'].includes(error?.name)) throw new HttpsError('deadline-exceeded', 'AI検索がタイムアウトしました。再試行してください。');
    // Do not log upstream response bodies, keys, user context or error messages.
    throw new HttpsError('unavailable', 'AIとの通信に失敗しました。');
  }
}
module.exports = {getMatchingSpots, getAiRecommendations, serializeSpot, validateInput, loadCandidates, rateLimit, parseRecommendations};
