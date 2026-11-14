'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { searchDrivingRoute } = require('./driving_route');
const request = () => ({ auth: { uid: 'guest' }, data: {
  from: { name: '札幌駅', address: '札幌市北区', latitude: 43.06, longitude: 141.35 },
  to: { name: '観光地', address: '夕張市' },
}});
test('server calls DRIVE with a limited field mask and returns no credentials', async () => {
  const result = await searchDrivingRoute(request(), () => 'test-secret', async (url, options) => {
    assert.equal(url, 'https://routes.googleapis.com/directions/v2:computeRoutes');
    assert.equal(options.headers['X-Goog-FieldMask'], 'routes.duration,routes.distanceMeters');
    const body = JSON.parse(options.body);
    assert.equal(body.travelMode, 'DRIVE');
    assert.equal(body.routingPreference, 'TRAFFIC_UNAWARE');
    assert.deepEqual(body.origin, { location: { latLng: { latitude: 43.06, longitude: 141.35 } } });
    assert.equal(body.destination.address, '観光地 夕張市');
    return { ok: true, json: async () => ({ routes: [{ duration: '1234.5s', distanceMeters: 12000 }] }) };
  });
  assert.deepEqual(result, { durationSeconds: 1235, distanceMeters: 12000, provider: 'google_routes', trafficAware: false });
  assert(!JSON.stringify(result).includes('test-secret'));
});
test('auth, endpoints and configuration are checked before calling the API', async () => {
  const noFetch = () => assert.fail('API must not be called');
  await assert.rejects(searchDrivingRoute({ data: {} }, () => 'secret', noFetch), e => e.code === 'unauthenticated');
  const invalid = request(); invalid.data.to = { name: 'unknown' };
  await assert.rejects(searchDrivingRoute(invalid, () => 'secret', noFetch), e => e.code === 'invalid-argument');
  await assert.rejects(searchDrivingRoute(request(), () => '', noFetch), e => e.code === 'failed-precondition');
});
test('empty, malformed and upstream errors have public messages', async () => {
  for (const [response, code] of [
    [{ routes: [] }, 'not-found'],
    [{ routes: [{ duration: 'bad', distanceMeters: 1 }] }, 'unavailable'],
    [{ routes: [{ duration: '1s', distanceMeters: -1 }] }, 'unavailable'],
  ]) {
    await assert.rejects(searchDrivingRoute(request(), () => 'secret', async () => ({ ok: true, json: async () => response })), e => e.code === code);
  }
  await assert.rejects(searchDrivingRoute(request(), () => 'secret', async () => { throw Error('private'); }), e => e.code === 'unavailable' && !e.message.includes('private'));
});
