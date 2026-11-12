"use strict";
// Preparation only: no route search, LLM, or Dify HTTP requests here.
const { validDate, operates } = require('./transport_router');
const { distanceMeters } = require('./transport_nearby_stops');
const DAY = 86400;
class PreparationError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const fail = (message) => { throw new PreparationError('invalid-argument', message); };
function validateInput(q) {
  if (!q || !validDate(q.date) || !Number.isInteger(q.departureSeconds) || q.departureSeconds < 0 || q.departureSeconds >= DAY ||
    !Number.isInteger(q.deadlineSeconds) || q.deadlineSeconds <= q.departureSeconds || q.deadlineSeconds > q.departureSeconds + 2 * DAY) fail('旅行日・出発時刻・到着期限（出発から48時間以内）が不正です');
  if (!Array.isArray(q.visits) || q.visits.length < 1 || q.visits.length > 3) fail('観光地は1〜3件です');
  const ids = new Set();
  for (const place of [q.origin, ...q.visits, q.destination]) {
    if (!place || typeof place.id !== 'string' || !place.id.length || place.id.length > 1400 || typeof place.name !== 'string' || place.name.length > 500) fail('地点ID・名称が不正です');
    if ((place.latitude != null || place.longitude != null) && (!Number.isFinite(place.latitude) || Math.abs(place.latitude) > 90 || !Number.isFinite(place.longitude) || Math.abs(place.longitude) > 180)) fail('地点座標が不正です');
    if (!Array.isArray(place.accessStops) || place.accessStops.length > 30) fail('徒歩接続は地点ごとに最大30件です');
    for (const a of place.accessStops) {
      if (!a || typeof a.stopId !== 'string' || !a.stopId.length || a.stopId.length > 1400 ||
        (a.walkingMinutes != null && (!Number.isInteger(a.walkingMinutes) || a.walkingMinutes < 0 || a.walkingMinutes > 1440))) fail('徒歩接続が不正です');
    }
  }
  for (const v of q.visits) {
    if (ids.has(v.id)) fail('観光地IDが重複しています');
    ids.add(v.id);
    if (!Number.isInteger(v.staySeconds) || v.staySeconds <= 0 || v.staySeconds > DAY) fail('滞在時間が不正です');
    if (!v.opening || !['known', 'closed', 'unknown'].includes(v.opening.status) || !Array.isArray(v.opening.windows) || v.opening.windows.length > 20) fail('旅行日の営業時間が不正です');
    if (v.opening.status !== 'known' && v.opening.windows.length) fail('営業時間の状態と時間帯が矛盾しています');
    if (v.opening.status === 'known' && !v.opening.windows.length) fail('営業時間を指定してください');
    for (const w of v.opening.windows) if (!Array.isArray(w) || w.length !== 2 || !w.every(Number.isInteger) || w[0] < 0 || w[1] <= w[0] || w[1] > 3 * DAY) fail('営業時間帯が不正です');
  }
  if (!Array.isArray(q.modes) || !q.modes.length || q.modes.some((m) => !['rail', 'bus', 'walk'].includes(m))) fail('交通手段が不正です');
  if (!['travel_time', 'transfers', 'walking'].includes(q.preference)) fail('優先条件が不正です');
  if (!Number.isInteger(q.minimumTransferSeconds) || q.minimumTransferSeconds < 180 || q.minimumTransferSeconds > 3600) fail('乗換余裕は180〜3600秒です');
  return q;
}
const pick = (obj, keys) => Object.fromEntries(keys.filter((k) => obj[k] != null).map((k) => [k, obj[k]]));
function buildPayload(network, input, { maxBytes = 500000, versions = {} } = {}) {
  const q = validateInput(input), instances = [], segments = [], stopIds = new Set(), routeIds = new Set(), warnings = new Set();
  const base = Date.parse(q.date);
  for (const t of network.trips) {
    const route = network.routes.get(t.routeId);
    const mode = route?.routeType === 3 || route?.mode === 'bus' ? 'bus' : [0, 1, 2].includes(route?.routeType) || ['rail', 'tram', 'subway'].includes(route?.mode) ? 'rail' : null;
    if (!mode) throw new PreparationError('failed-precondition', `路線種別が未対応または不明です: ${t.routeId}`);
    if (!q.modes.includes(mode)) continue;
    if (!route.agencyId || !network.agencies?.has(route.agencyId)) throw new PreparationError('failed-precondition', `事業者情報が不足しています: ${t.routeId}`);
    const values = t.times.flatMap((s) => [s[2], s[3]]).filter(Number.isInteger);
    if (!values.length) continue;
    const min = Math.min(...values), max = Math.max(...values);
    for (let day = Math.ceil((q.departureSeconds - max) / DAY); day <= Math.floor((q.deadlineSeconds - min) / DAY); day++) {
      const serviceDate = new Date(base + day * DAY * 1000).toISOString().slice(0, 10);
      if (!operates(network.services.get(t.serviceId), serviceDate)) continue;
      const id = `${t.id}@${serviceDate}`, times = t.times.map((s) => [s[0], s[1], s[2] == null ? null : s[2] + day * DAY, s[3] == null ? null : s[3] + day * DAY, s[4], s[5]]);
      const edges = [];
      for (let i = 1; i < times.length; i++) {
        const a = times[i - 1], b = times[i];
        if (a[3] == null || b[2] == null) { warnings.add('時刻未登録区間は補間せず除外しています'); continue; }
        if (b[2] < a[3]) throw new PreparationError('data-loss', '便の時刻順序が不正です');
        if (a[3] < q.departureSeconds || b[2] > q.deadlineSeconds) continue;
        if (!network.stops.has(a[0]) || !network.stops.has(b[0])) throw new PreparationError('data-loss', '停留所参照が不足しています');
        edges.push({ instanceId: id, fromStopId: a[0], toStopId: b[0], fromSequence: a[1], toSequence: b[1], departureSeconds: a[3], arrivalSeconds: b[2], pickup: a[4], dropoff: b[5] });
        stopIds.add(a[0]); stopIds.add(b[0]);
      }
      if (edges.length) { instances.push({ id, tripId: t.id, routeId: t.routeId, serviceDate, feedId: t.feedId ?? null, versionId: t.versionId ?? null, verificationStatus: t.verificationStatus ?? 'unverified' }); segments.push(...edges);
        if (segments.length > 100000) throw new PreparationError('resource-exhausted', '区間数が抽出上限を超えています。時間帯の縮小が必要です');
        routeIds.add(t.routeId); }
    }
  }
  const places = [q.origin, ...q.visits, q.destination].map((p, i) => {
    const access = p.accessStops.map((a) => {
      const stop = network.stops.get(a.stopId);
      if (!stop) throw new PreparationError('failed-precondition', `徒歩接続先が存在しません: ${a.stopId}`);
      stopIds.add(a.stopId);
      const distance = distanceMeters(p, stop);
      const confirmed = a.verificationStatus === 'verified' && a.sourceType !== 'sample' && a.walkingMinutes != null;
      return { stopId: a.stopId, seconds: a.walkingMinutes != null ? a.walkingMinutes * 60 : distance == null ? null : Math.ceil(distance / 60) * 60,
        source: a.walkingMinutes != null ? 'registered' : distance == null ? 'unknown' : 'straight_line_estimate', usableForRouting: q.modes.includes('walk') && confirmed, estimated: !confirmed };
    });
    return { ...pick(p, ['id', 'name', 'latitude', 'longitude']), role: i === 0 ? 'origin' : i === placesLength(q) - 1 ? 'destination' : 'visit', accessStops: access,
      ...(i > 0 && i <= q.visits.length ? { staySeconds: p.staySeconds, opening: { status: p.opening.status, windows: p.opening.windows } } : {}) };
  });
  // Preserve contextual prohibitions and parent-station expansion from the existing reader.
  const transfers = [];
  for (const [pair, rules] of network.rules) {
    const [fromStopId, toStopId] = pair.split('\n');
    if (!stopIds.has(fromStopId) || !stopIds.has(toStopId)) continue;
    for (const r of rules) transfers.push({ ...pick(r, ['id', 'transferType', 'minTransferSeconds', 'fromRouteId', 'toRouteId', 'fromTripId', 'toTripId', 'sourceType', 'verificationStatus']), fromStopId, toStopId, usableForRouting: ![3, 4, 5].includes(r.transferType) && (fromStopId === toStopId || (q.modes.includes('walk') && Number.isInteger(r.minTransferSeconds))) });
  }
  const payload = { schemaVersion: 1, workflow: 'TABISAKI_Transport_Optimizer', date: q.date, timezone: 'Asia/Tokyo', timeUnit: 'seconds_since_trip_date_midnight',
    departureSeconds: q.departureSeconds, deadlineSeconds: q.deadlineSeconds, modes: q.modes, preference: q.preference, minimumTransferSeconds: q.minimumTransferSeconds,
    policy: { evaluateAllVisitPermutations: true, allowEstimatedWalking: false, unknownOpeningRequiresReview: true, sameStopTransferBufferSeconds: q.minimumTransferSeconds, transferSpecificity: ['both_trips', 'trip_and_opposite_route', 'one_trip', 'both_routes', 'one_route', 'stops'], prohibitedTransferTypes: [3, 4, 5], continueOnSameInstanceWithoutTransfer: true },
    places, stops: [...stopIds].map((id) => pick(network.stops.get(id), ['id', 'name', 'latitude', 'longitude', 'parentStationId', 'platformCode'])),
    routes: [...routeIds].map((id) => pick(network.routes.get(id), ['id', 'name', 'routeType', 'mode', 'agencyId'])),
    agencies: [...new Set([...routeIds].map((id) => network.routes.get(id).agencyId))].map((id) => pick(network.agencies.get(id), ['id', 'name', 'timezone'])),
    instances, segments, transfers, versions, warnings: [...warnings] };
  const json = JSON.stringify(payload), bytes = Buffer.byteLength(json);
  if (bytes > maxBytes) throw new PreparationError('resource-exhausted', `交通JSONは${bytes} bytes（上限${maxBytes}）。切捨ては行いません。時間帯縮小または接続を保持する部分グラフ索引が必要です`);
  return { payload, json, bytes };
}
function placesLength(q) { return q.visits.length + 2; }
module.exports = { validateInput, buildPayload, PreparationError };
