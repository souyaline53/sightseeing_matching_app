'use strict';
const { HttpsError } = require('firebase-functions/v2/https');

function waypoint(value) {
  if (!value || typeof value !== 'object') throw new HttpsError('invalid-argument', '出発地と目的地が必要です。');
  const { latitude, longitude, name, address } = value;
  if (Number.isFinite(latitude) && Number.isFinite(longitude) && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180) {
    return { location: { latLng: { latitude, longitude } } };
  }
  if (typeof name !== 'string' || typeof address !== 'string' || !address.trim() || name.length > 200 || address.length > 500) {
    throw new HttpsError('invalid-argument', '場所の住所または緯度・経度を登録してください。');
  }
  return { address: `${name.trim()} ${address.trim()}`.trim() };
}

async function searchDrivingRoute(request, getApiKey, fetchRoute = fetch) {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', '認証が必要です。');
  const origin = waypoint(request.data?.from), destination = waypoint(request.data?.to);
  let key;
  try { key = getApiKey(); } catch (_) { /* Return a public configuration message. */ }
  if (!key) throw new HttpsError('failed-precondition', '車ルート検索の接続設定を確認してください。');
  try {
    const response = await fetchRoute('https://routes.googleapis.com/directions/v2:computeRoutes', {
      method: 'POST', signal: AbortSignal.timeout(15000),
      headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': key,
        'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters' },
      body: JSON.stringify({ origin, destination, travelMode: 'DRIVE',
        routingPreference: 'TRAFFIC_UNAWARE', languageCode: 'ja-JP', units: 'METRIC' }),
    });
    if (!response.ok) throw new Error('upstream');
    const route = (await response.json()).routes?.[0];
    if (!route) throw new HttpsError('not-found', '車で移動できるルートが見つかりませんでした。');
    const duration = typeof route.duration === 'string' && /^(\d+(\.\d+)?)s$/.test(route.duration)
      ? Number(route.duration.slice(0, -1)) : NaN;
    if (!Number.isFinite(duration) || duration < 0 || !Number.isFinite(route.distanceMeters) || route.distanceMeters < 0) throw new Error('invalid-response');
    return { durationSeconds: Math.ceil(duration), distanceMeters: route.distanceMeters,
      provider: 'google_routes', trafficAware: false };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('unavailable', '車ルートを取得できませんでした。時間をおいて再試行してください。');
  }
}
module.exports = { searchDrivingRoute };
