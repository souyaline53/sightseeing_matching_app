'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const p = require('../docs/transport_optimizer_meroad_coal_network.json');
const q = require('../docs/transport_optimizer_meroad_coal_request.json');
const { validateInput } = require('./transport_optimizer');
test('two-place network preserves schema, actual references, transfer rules, alternatives and capacity', () => {
  validateInput(q);
  assert.equal(p.schemaVersion, 1);
  assert.equal(p.date, '2026-11-01');
  assert.deepEqual(p.places.filter((v) => v.role === 'visit').map((v) => v.id), ['melon', 'coal']);
  for (const k of ['status', 'candidates', 'legs', 'selectedCandidateId']) assert(!(k in p));
  assert(fs.statSync(require.resolve('../docs/transport_optimizer_meroad_coal_network.json')).size <= 500000);
  const instances = new Set(p.instances.map((r) => r.id)), stops = new Set(p.stops.map((r) => r.id));
  for (const s of p.segments) {
    assert(instances.has(s.instanceId));
    assert(stops.has(s.fromStopId) && stops.has(s.toStopId));
    assert(s.departureSeconds >= p.departureSeconds && s.arrivalSeconds <= p.deadlineSeconds);
    assert(s.fromSequence < s.toSequence);
  }
  assert.equal(p.transfers.length, 2);
  assert(p.transfers.every((r) => r.minTransferSeconds === 300 && r.transferType === 2));
  assert(p.instances.length > 4);
  assert.equal(p.places.find((v) => v.id === 'coal').accessStops[0].seconds, 600);
});

test('registered train/bus edges permit Meroad then 90-minute museum visit and Sapporo return before 17:00', () => {
  const sapporo = q.origin.accessStops[0].stopId;
  const meroad = q.visits.find((v) => v.id === 'melon');
  const museum = q.visits.find((v) => v.id === 'coal');
  const jr = meroad.accessStops[0].stopId, bus = meroad.accessStops[1].stopId, coal = museum.accessStops[0].stopId;
  function ride(from, to, departure) {
    for (const first of p.segments.filter((s) => s.fromStopId === from && s.departureSeconds === departure && s.pickup)) {
      let edge = first;
      const seen = new Set();
      while (edge && !seen.has(edge.fromSequence)) {
        seen.add(edge.fromSequence);
        if (edge.toStopId === to && edge.dropoff) return edge.arrivalSeconds;
        const prior = edge;
        edge = p.segments.find((s) => s.instanceId === prior.instanceId && s.fromStopId === prior.toStopId && s.fromSequence === prior.toSequence && s.departureSeconds >= prior.arrivalSeconds);
      }
    }
    assert.fail('witness must use actual contiguous network edges');
  }
  // Validation witness only: no chosen itinerary is embedded into the JSON input.
  const arrivalAtJR = ride(sapporo, jr, 31920); // 08:52 train
  let arrival = arrivalAtJR + 300, leave = arrival + meroad.staySeconds;
  assert(meroad.opening.windows.some(([a, b]) => a <= arrival && leave <= b));
  assert(leave + 180 + 180 <= 41280); // 3min walk, 3min boarding allowance
  const busArrival = ride(bus, coal, 41280); // 11:28 bus
  arrival = busArrival + 600;
  leave = arrival + museum.staySeconds;
  assert(museum.opening.windows.some(([a, b]) => a <= arrival && leave <= b));
  assert(arrival <= 15.5 * 3600); // final admission at 15:30
  assert(leave + 600 + 180 <= 52500); // 14:35 return bus
  const returnBusArrival = ride(coal, bus, 52500);
  const transfer = p.transfers.find((t) => t.fromStopId === bus && t.toStopId === jr);
  assert(returnBusArrival + Math.max(p.minimumTransferSeconds, transfer.minTransferSeconds) <= 56160);
  const home = ride(jr, sapporo, 56160); // 15:36 train
  assert.equal(home, 60000); // 16:40
  assert(home <= p.deadlineSeconds);
});
