'use strict';
// Existing local router as a regression oracle for explicit v1 connections only.
// This is NOT a substitute for executing the deployment's Dify Python Code ②/③.
const { prepareNetwork, searchJourneys } = require('../transport_router');
function toNetwork(p) {
  const groups = new Map(), source = new Map(p.instances.map((i) => [i.id, i]));
  for (const s of p.segments) { if (!groups.has(s.instanceId)) groups.set(s.instanceId, []); groups.get(s.instanceId).push(s); }
  const trips = [];
  for (const [id, edges] of groups) {
    edges.sort((a, b) => a.fromSequence - b.fromSequence);
    let chunk = [], last;
    const flush = () => {
      if (!chunk.length) return;
      const i = source.get(id), times = [];
      for (const s of chunk) {
        if (!times.length) times.push([s.fromStopId, s.fromSequence, null, s.departureSeconds, s.pickup, false]);
        else { times.at(-1)[3] = s.departureSeconds; times.at(-1)[4] = s.pickup; }
        times.push([s.toStopId, s.toSequence, s.arrivalSeconds, null, false, s.dropoff]);
      }
      trips.push({ id: `${id}#${chunk[0].fromSequence}`, routeId: i.routeId, serviceId: 'day', times, verificationStatus: i.verificationStatus }); chunk = [];
    };
    for (const s of edges) {
      if (last && (last.toSequence !== s.fromSequence || last.toStopId !== s.fromStopId)) flush();
      chunk.push(s); last = s;
    }
    flush();
  }
  // Rewrite scoped rule IDs to each split instance chunk. Preserve prohibition fields.
  const transfers = p.transfers.flatMap((t) => {
    const matching = (id) => trips.filter((trip) => trip.id.startsWith(`${id}@`) || trip.id.startsWith(`${id}#`)).map((v) => v.id);
    const from = t.fromTripId ? matching(t.fromTripId) : [null], to = t.toTripId ? matching(t.toTripId) : [null];
    return from.flatMap((a) => to.map((b) => ({ ...t, ...(a ? { fromTripId: a } : {}), ...(b ? { toTripId: b } : {}) })));
  });
  return prepareNetwork([{ stops: p.stops, routes: p.routes, sameNameConnections: [],
    services: [{ id: 'day', validFrom: p.date, validTo: p.date, weekdays: [1, 2, 3, 4, 5, 6, 7] }], trips, transfers }]);
}
function evaluate(p, order) {
  const net = toNetwork(p), origin = p.places.find((v) => v.role === 'origin'), destination = p.places.find((v) => v.role === 'destination');
  let states = [{ time: p.departureSeconds, visits: [], legs: [], transfers: 0, walkingSeconds: 0, requiresReview: false }];
  let from = origin;
  const warnings = new Set();
  for (const to of [...order, destination]) {
    const access = (place) => place.accessStops.filter((a) => a.usableForRouting && a.seconds != null).map((a) => ({ stopId: a.stopId, walkingMinutes: a.seconds / 60 }));
    const next = [];
    for (const state of states) {
      if (!access(from).length || !access(to).length) continue;
      const result = searchJourneys(net, { date: p.date, departureSeconds: state.time, maxTransfers: 3,
        minimumTransferSeconds: p.minimumTransferSeconds, from: access(from), to: access(to) });
      for (const w of result.warnings) warnings.add(w);
      for (const journey of result.journeys) {
        let time = journey.arrivalSeconds;
        if (time > p.deadlineSeconds) continue;
        const visits = [...state.visits];
        if (to.role === 'visit') {
          if (to.opening.status === 'closed') continue;
          if (to.opening.status === 'known') {
            const window = to.opening.windows.find(([a, b]) => Math.max(time, a) + to.staySeconds <= b);
            if (!window) continue;
            time = Math.max(time, window[0]);
          }
          visits.push({ id: to.id, arrival: journey.arrivalSeconds, start: time, departure: time + to.staySeconds }); time += to.staySeconds;
        }
        next.push({ time, visits, legs: [...state.legs, ...journey.legs.map((l) => ({ trip: l.tripId.split('#')[0], from: l.boardingStopId, to: l.alightingStopId, departure: l.departureSeconds, arrival: l.arrivalSeconds }))],
          transfers: state.transfers + journey.transferCount, walkingSeconds: state.walkingSeconds + (journey.walkingMinutesBefore + journey.walkingMinutesAfter) * 60,
          requiresReview: state.requiresReview || journey.verificationStatus !== 'verified' || (to.role === 'visit' && to.opening.status === 'unknown') });
      }
    }
    states = next; from = to;
  }
  return { journeys: states.sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b))), warnings: [...warnings].sort() };
}
module.exports = { evaluate };
