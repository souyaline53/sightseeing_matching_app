'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateInput } = require('./transport_optimizer');
const { generate } = require('../tool/meroad_transport_sample.cjs');
const request = require('../docs/transport_optimizer_meroad_request.json');
const payload = require('../docs/transport_optimizer_sample.json');
const report = require('../docs/transport_optimizer_meroad_extraction.json');
test('schema v1 input network has both directions, alternatives and original transfer rules without an itinerary answer', () => {
  validateInput(request);
  assert.equal(payload.schemaVersion, 1);
  assert.equal(payload.date, '2026-11-13');
  for (const field of ['status', 'candidates', 'legs', 'selectedCandidateId', 'sampleEvidence']) assert(!(field in payload));
  assert.equal(Buffer.byteLength(JSON.stringify(payload)), report.bytes);
  assert(report.bytes < 500000);
  assert.deepEqual(payload.modes, ['rail', 'bus', 'walk']);
  const stops = new Set(payload.stops.map((s) => s.id));
  const instances = new Map(payload.instances.map((s) => [s.id, s]));
  const routes = new Map(payload.routes.map((s) => [s.id, s]));
  const agencies = new Set(payload.agencies.map((s) => s.id));
  for (const r of routes.values()) assert(agencies.has(r.agencyId));
  for (const s of payload.segments) {
    assert(stops.has(s.fromStopId) && stops.has(s.toStopId));
    assert(instances.has(s.instanceId));
    assert(routes.has(instances.get(s.instanceId).routeId));
    assert(s.departureSeconds >= payload.departureSeconds && s.arrivalSeconds <= payload.deadlineSeconds);
    assert(s.arrivalSeconds >= s.departureSeconds);
  }
  const from = request.origin.accessStops[0].stopId, to = request.visits[0].accessStops[0].stopId;
  const hasPathInTrip = (a, b) => [...instances.keys()].filter((id) => {
    const edges = payload.segments.filter((s) => s.instanceId === id).sort((x, y) => x.fromSequence - y.fromSequence);
    const start = edges.findIndex((s) => s.fromStopId === a && s.pickup);
    if (start < 0) return false;
    for (let i = start; i < edges.length; i++) {
      if (i > start && (edges[i - 1].toStopId !== edges[i].fromStopId || edges[i - 1].toSequence !== edges[i].fromSequence)) return false;
      if (edges[i].toStopId === b && edges[i].dropoff) return true;
    }
    return false;
  });
  assert(hasPathInTrip(from, to).length >= 2, 'alternative outbound trains retained');
  assert(hasPathInTrip(to, from).length >= 2, 'alternative inbound trains retained');
  assert([...routes.values()].some((r) => r.routeType === 3));
  assert.equal(payload.transfers.length, 2);
  assert.deepEqual(new Set(payload.transfers.map((r) => r.id)), new Set(['shinyubaristation', 'shinyuubaristationup']));
  for (const r of payload.transfers) {
    assert(stops.has(r.fromStopId) && stops.has(r.toStopId));
    assert.equal(r.transferType, 2);
    assert.equal(r.minTransferSeconds, 300);
    assert.equal(r.verificationStatus, 'unverified');
  }
});

test('extractor retains unsupported/scoped transfer rules and intermediate stops outside the corridor', () => {
  const a = 'jr_hokkaido~SlJfQUYwNzEzMjM4Qg', b = 'jr_hokkaido~SlJfN0Q4QjI2RDEzNA';
  const bus = 'yutetsu_bus~UzAxODEwMDAxNzcwMDEwMA';
  const stops = [{ id: a, name: '札幌', latitude: 43, longitude: 141 }, { id: 'outside', name: '区域外途中駅' }, { id: b, name: '新夕張' }, { id: bus, name: '新夕張駅前' }];
  const time = (id, seq, seconds) => [id, seq, seconds, seconds, true, true];
  const railTrip = { id: 'rail-trip', routeId: 'rail', feedId: 'jr_hokkaido', versionId: 'v', serviceId: 'service', times: [time(a, 1, 39000), time('outside', 2, 40000), time(b, 3, 41000)] };
  const busTrip = { id: 'bus-trip', routeId: 'bus', feedId: 'yutetsu_bus', versionId: 'v', serviceId: 'service', times: [time(bus, 1, 42000), time(b, 2, 43000)] };
  const rule = { id: 'unsupported', fromStopId: b, toStopId: bus, transferType: 4, fromTripId: 'rail-trip', toRouteId: 'bus', note: 'retain unsupported rule', sourceUrl: 'https://example.test/rule' };
  const network = { stops: new Map(stops.map((s) => [s.id, s])), routes: new Map([['rail', { id: 'rail', routeType: 2, agencyId: 'agency' }], ['bus', { id: 'bus', routeType: 3, agencyId: 'agency' }]]), agencies: new Map([['agency', { id: 'agency' }]]), services: new Map([['service', { id: 'service', validFrom: '2026-11-13', validTo: '2026-11-13', weekdays: [5] }]]), trips: [railTrip, busTrip], rules: new Map([[`${b}\n${bus}`, [rule]]]) };
  const sample = generate(network);
  assert(sample.payload.stops.some((s) => s.id === 'outside'));
  const exported = sample.payload.transfers[0];
  for (const [key, value] of Object.entries(rule)) assert.deepEqual(exported[key], value);
  assert.equal(exported.usableForRouting, false);
});
