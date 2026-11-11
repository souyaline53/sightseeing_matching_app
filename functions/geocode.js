const { HttpsError } = require('firebase-functions/v2/https');
async function geocodeAddress(request) {
  const token = request.auth?.token;
  if (token?.email?.toLowerCase() !== 'nichi-ka@nichi-ka.com' || token.email_verified !== true) {
    throw new HttpsError('permission-denied', 'メール確認済みの管理者アカウントが必要です。');
  }
  const address = request.data?.address;
  if (typeof address !== 'string' || !address.trim() || address.length > 500) {
    throw new HttpsError('invalid-argument', '住所を500文字以内で入力してください。');
  }
  try {
    const url = new URL('https://msearch.gsi.go.jp/address-search/AddressSearch');
    url.searchParams.set('q', address.trim());
    const response = await fetch(url, { signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error('upstream');
    const results = await response.json();
    if (!Array.isArray(results) || results.length !== 1) {
      throw new HttpsError('not-found', '住所の位置を一意に特定できません。住所を詳しく入力するか、緯度・経度を指定してください。');
    }
    const [longitude, latitude] = results[0].geometry?.coordinates ?? [];
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) throw new Error('coordinates');
    return { latitude, longitude };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('unavailable', '住所を変換できませんでした。再試行するか緯度・経度を指定してください。');
  }
}
module.exports = { geocodeAddress };
