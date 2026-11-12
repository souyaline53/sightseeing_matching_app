'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseFiles } = require('./transport_bundle');
const { fixture } = require('./test_support/gtfs_fixture');
const { routingData } = require('./transport_routing_bundle');
const { prepareNetwork } = require('./transport_router');
const { buildPayload } = require('./transport_optimizer');
function setup() {
  const parsed = parseFiles(fixture(), 'test');
  assert.deepEqual(parsed.errors, []);
  const net = prepareNetwork([routingData(parsed.data, 'v1')]);
  net.routes = new Map(parsed.data.routes.map((r) => [r.id, r]));
  net.agencies = new Map(parsed.data.agencies.map((r) => [r.id, r]));
  const stops = [...net.stops.keys()];
  const place = (id, stopId) => ({ id, name: id, accessStops: [{ stopId, walkingMinutes: 5, verificationStatus: 'verified' }] });
  const q = { date: '2026-01-02', departureSeconds: 0, deadlineSeconds: 7200,
    origin: place('start', stops[0]), destination: place('end', stops[2]),
    visits: [{ ...place('spot', stops[1]), staySeconds: 600, opening: { status: 'unknown', windows: [] } }],
    modes: ['bus', 'rail', 'walk'], preference: 'travel_time', minimumTransferSeconds: 180 };
  return { net, q, stops };
}
test('previous service day, >24h seconds, intermediate stops, same instance and boarding restrictions', () => {
  const { net, q, stops } = setup();
  const { payload, json, bytes } = buildPayload(net, q);
  assert.equal(payload.instances.length, 1);
  assert.equal(payload.instances[0].serviceDate, '2026-01-01');
  assert.equal(payload.segments.length, 2);
  assert.equal(payload.segments[0].departureSeconds, 631);
  assert.equal(payload.segments[1].arrivalSeconds, 3600);
  assert.equal(payload.segments[0].instanceId, payload.segments[1].instanceId);
  assert.equal(payload.segments[0].dropoff, true);
  assert.equal(payload.segments[1].pickup, true);
  assert(payload.stops.some((s) => s.id === stops[1]));
  assert.equal(payload.agencies[0].name, '夕鉄バス');
  assert.equal(bytes, Buffer.byteLength(json));
  assert.deepEqual(JSON.parse(json), payload);
});
test('calendar removal, addition, weekend and next-day service', () => {
  const { net, q } = setup();
  // Jan 2 service is explicitly removed; Jan 3 is explicitly added (Saturday).
  assert.equal(buildPayload(net, { ...q, date: '2026-01-03' }).payload.instances.length, 0);
  assert.equal(buildPayload(net, { ...q, date: '2026-01-04' }).payload.instances.length, 1);
  assert.equal(buildPayload(net, { ...q, date: '2026-01-05' }).payload.instances.length, 0);
  const p = buildPayload(net, { ...q, date: '2026-01-01', departureSeconds: 86000, deadlineSeconds: 92000 }).payload;
  assert.equal(p.instances[0].serviceDate, '2026-01-01');
  assert.equal(p.segments[0].departureSeconds, 87031);
});
test('unverified, missing and estimated walking never becomes a confirmed edge', () => {
  const { net, q } = setup();
  q.origin.latitude = 43; q.origin.longitude = 141;
  delete q.origin.accessStops[0].walkingMinutes;
  const p = buildPayload(net, q).payload;
  assert.equal(p.places[0].accessStops[0].source, 'straight_line_estimate');
  assert.equal(p.places[0].accessStops[0].usableForRouting, false);
  assert.equal(p.places[1].opening.status, 'unknown');
  q.origin.accessStops[0].walkingMinutes = 5;
  q.origin.accessStops[0].verificationStatus = 'unverified';
  assert.equal(buildPayload(net, q).payload.places[0].accessStops[0].usableForRouting, false);
});
test('directional contextual transfer bans and parent expansion are preserved', () => {
  const { net, q, stops } = setup();
  net.rules.set(`${stops[0]}\n${stops[1]}`, [{ id: 'ban', transferType: 3, fromTripId: net.trips[0].id }]);
  const p = buildPayload(net, q).payload;
  assert.equal(p.transfers[0].transferType, 3);
  assert.equal(p.transfers[0].fromTripId, net.trips[0].id);
  assert.equal(p.transfers.length, 1);
  assert.equal(p.minimumTransferSeconds, 180);
});
test('invalid constraints, missing metadata and capacity fail rather than truncate', () => {
  const { net, q } = setup();
  assert.throws(() => buildPayload(net, { ...q, date: '2026-02-30' }), /旅行日/);
  assert.throws(() => buildPayload(net, { ...q, visits: Array(4).fill(q.visits[0]) }), /1〜3/);
  assert.throws(() => buildPayload(net, { ...q, deadlineSeconds: 0 }), /到着期限/);
  assert.throws(() => buildPayload(net, q, { maxBytes: 10 }), (e) => e.code === 'resource-exhausted');
  net.routes.get(net.trips[0].routeId).routeType = null;
  assert.throws(() => buildPayload(net, q), (e) => e.code === 'failed-precondition');
});
test('selected modes and deadline filter only complete adjacent segments', () => {
  const { net, q } = setup();
  assert.equal(buildPayload(net, { ...q, modes: ['rail', 'walk'] }).payload.segments.length, 0);
  const p = buildPayload(net, { ...q, deadlineSeconds: 1300 }).payload;
  assert.equal(p.segments.length, 1);
  assert.equal(p.segments[0].arrivalSeconds, 1200);
});
test('callable uses Firestore version metadata and verified Storage catalog without Dify', async () => {
  const { compileBundle } = require('./transport_bundle');
  const { prepareTransportOptimization } = require('./transport_optimizer_api');
  const parsed = parseFiles(fixture(), 'test');
  const bundle = compileBundle(parsed, 'test', 'test-v-api');
  const objects = new Map(bundle.objects.map((o) => [o.path, o.bytes]));
  const feed = { activeVersionId: 'test-v-api', distribution: { routing: bundle.routing,
    manifestPath: bundle.manifestPath, manifestChecksum: bundle.manifestChecksum, manifestBytes: bundle.manifestBytes } };
  let downloads = 0;
  const bucket = { file: (path) => ({ download: async () => { downloads++; return [objects.get(path)]; } }) };
  const db = {
    collection: (name) => {
      const docs = name === 'transport_feeds' ? [{ id: 'test', data: () => feed }] : [];
      const query = { orderBy: () => query, limit: () => query, get: async () => ({ docs, size: docs.length }) };
      return query;
    },
    doc: () => ({ get: async () => ({ data: () => ({ revision: 'test-api' }) }) }),
  };
  const { q } = setup();
  await assert.rejects(() => prepareTransportOptimization({ data: q }, db, bucket), (e) => e.code === 'unauthenticated');
  const result = await prepareTransportOptimization({ auth: { uid: 'mock' }, data: q }, db, bucket);
  const payload = JSON.parse(result.inputs.transport_json);
  assert.equal(payload.routes[0].routeType, 3);
  assert.equal(payload.agencies[0].name, '夕鉄バス');
  assert.equal(payload.segments.length, 2);
  assert.equal(downloads, 3);
  await prepareTransportOptimization({ auth: { uid: 'mock' }, data: q }, db, bucket);
  assert.equal(downloads, 3, 'warm calls reuse immutable network and catalog');
});
