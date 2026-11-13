'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { metrics, serialize, deduplicate, connectedNetwork, pruneUnreachable, TransportPayloadCache, cacheKey } = require('./transport_payload_optimizer');
const { measureFirestore } = require('./transport_read_metrics');
function fixture() {
  return { schemaVersion: 1, date: '2026-11-01', departureSeconds: 0, deadlineSeconds: 100,
    places: [{ role: 'origin', accessStops: [{ stopId: 'a' }] }, { role: 'visit', accessStops: [{ stopId: 'v' }], staySeconds: 5 }, { role: 'destination', accessStops: [{ stopId: 'd' }] }],
    stops: ['a', 'b', 'c', 'v', 'd', 'far'].map((id) => ({ id })), routes: [{ id: 'r' }], agencies: [{ id: 'operator' }],
    instances: ['out', 'in', 'unreachable', 'transfer'].map((id) => ({ id, verificationStatus: 'unverified' })),
    segments: [
      { instanceId: 'out', fromStopId: 'a', toStopId: 'b', fromSequence: 1, toSequence: 2, departureSeconds: 10, arrivalSeconds: 20, pickup: true, dropoff: false },
      { instanceId: 'out', fromStopId: 'b', toStopId: 'v', fromSequence: 2, toSequence: 3, departureSeconds: 20, arrivalSeconds: 30, pickup: false, dropoff: true },
      { instanceId: 'transfer', fromStopId: 'c', toStopId: 'v', fromSequence: 1, toSequence: 2, departureSeconds: 25, arrivalSeconds: 28, pickup: true, dropoff: true },
      { instanceId: 'in', fromStopId: 'v', toStopId: 'd', fromSequence: 1, toSequence: 2, departureSeconds: 50, arrivalSeconds: 60, pickup: true, dropoff: true },
      { instanceId: 'unreachable', fromStopId: 'far', toStopId: 'a', fromSequence: 1, toSequence: 2, departureSeconds: 5, arrivalSeconds: 6, pickup: true, dropoff: true },
    ], transfers: [{ id: 'scoped', fromStopId: 'b', toStopId: 'c', transferType: 3, fromTripId: 'out', toTripId: 'transfer', minTransferSeconds: 5 }], warnings: ['review'], policy: { allowEstimatedWalking: false } };
}
test('pruning preserves through-rides, contextual rules, array order and metadata, removes only unreachable edges', () => {
  const p = fixture(), before = JSON.stringify(p), o = pruneUnreachable(p);
  assert.deepEqual(o.segments, p.segments.slice(0, 4));
  assert.deepEqual(o.transfers, p.transfers);
  assert.deepEqual(o.stops, p.stops);
  assert.deepEqual(o.warnings, p.warnings);
  assert.equal(JSON.stringify(p), before);
  assert.equal(o.instances.length, 3);
});
test('equal-time chains and outward detours outside any geographic rectangle survive relaxation', () => {
  const p = fixture();
  p.segments = [
    { instanceId: 'in', fromStopId: 'far', toStopId: 'd', fromSequence: 2, toSequence: 3, departureSeconds: 10, arrivalSeconds: 10 },
    { instanceId: 'out', fromStopId: 'a', toStopId: 'far', fromSequence: 1, toSequence: 2, departureSeconds: 10, arrivalSeconds: 10 },
  ];
  assert.deepEqual(pruneUnreachable(p).segments, p.segments);
});
test('deduplication preserves nulls and warnings, conflicting identities fail closed', () => {
  const p = fixture(); p.stops[0].latitude = null; p.stops.push({ ...p.stops[0] }); p.segments.push({ ...p.segments[0] });
  const o = deduplicate(p);
  assert.equal(o.stops.length, 6); assert.equal(o.segments.length, 5); assert.equal(o.stops[0].latitude, null);
  p.stops.push({ id: 'a', name: 'conflict' });
  assert.throws(() => deduplicate(p), (e) => e.code === 'data-loss');
});
test('Unicode characters, UTF-16 and UTF-8 limits are measured independently and never truncate', () => {
  assert.deepEqual(metrics('札😀'), { characters: 2, utf16Units: 3, bytes: 7 });
  const p = { value: '札😀' }, original = JSON.stringify(p);
  assert.throws(() => serialize(p, { maxCharacters: 3 }), (e) => e.code === 'resource-exhausted');
  assert.throws(() => serialize(p, { maxBytes: 4 }), /bytes/);
  assert.equal(JSON.stringify(p), original);
});
test('cache respects version, policy, time, modes, access scope, TTL, byte bound and mutation isolation', () => {
  let now = 0;
  const cache = new TransportPayloadCache({ now: () => now, ttlMs: 10, maxBytes: 30 });
  cache.set('a', { value: 1 }); const hit = cache.get('a'); hit.value = 2;
  assert.equal(cache.get('a').value, 1);
  now = 10; assert.equal(cache.get('a'), null);
  cache.set('a', { value: 1 }); cache.set('b', { value: 2 }); cache.set('c', { value: 3 });
  assert.equal(cache.get('a'), null); assert(cache.bytes <= 30);
  const q = { date: '2026-11-01', departureSeconds: 0, deadlineSeconds: 100, modes: ['rail'], minimumTransferSeconds: 300,
    origin: { accessStops: [{ stopId: 'a' }] }, destination: { accessStops: [{ stopId: 'd' }] }, visits: [] };
  const key = cacheKey('v1', q, false);
  for (const [v, query, pruning] of [['v2', q, false], ['v1', { ...q, deadlineSeconds: 101 }, false], ['v1', { ...q, minimumTransferSeconds: 600 }, false], ['v1', { ...q, modes: ['bus'] }, false], ['v1', q, true]]) assert.notEqual(cacheKey(v, query, pruning), key);
});
test('read metrics count returned documents, document gets and empty queries without equating them to billable reads', async () => {
  const empty = { size: 0, docs: [] }, rows = { size: 2, docs: [{}, {}] };
  const db = { collection: (name) => { const q = { limit: () => q, get: async () => name === 'empty' ? empty : rows }; return q; }, doc: () => ({ get: async () => ({ exists: true }) }) };
  const measured = measureFirestore(db);
  await measured.db.collection('empty').limit(1).get(); await measured.db.collection('rows').get(); await measured.db.doc('revision').get();
  assert.deepEqual(measured.stats, { firestoreQueries: 2, firestoreDocumentGets: 1, firestoreReturnedDocuments: 3, firestoreEmptyQueries: 1 });
});

test('static component selection preserves remote detours and transfer-connected feeds', () => {
  const network = { trips: [
    { id: 'out', times: [['a'], ['far'], ['b']] },
    { id: 'bus', times: [['platform'], ['v']] },
    { id: 'disconnected', times: [['x'], ['y']] },
  ], rules: new Map([['b\nplatform', [{ transferType: 3 }]]]) };
  const q = { origin: { accessStops: [{ stopId: 'a' }] }, visits: [], destination: { accessStops: [{ stopId: 'v' }] } };
  assert.deepEqual(connectedNetwork(network, q).trips.map((t) => t.id), ['out', 'bus']);
});

test('mandatory visits preserve both orders, positive stays, overnight paths and contextual rules', () => {
  const p=fixture();
  p.places=[p.places[0],{role:'visit',accessStops:[{stopId:'v'}],staySeconds:5},{role:'visit',accessStops:[{stopId:'c'}],staySeconds:5},p.places[2]];
  p.segments=[
    ['a','v',10,20],['v','c',30,40],['c','d',50,60],
    ['a','c',10,20],['c','v',30,40],['v','d',50,60],
    ['a','b',45,46],['b','d',47,48],
  ].map(([fromStopId,toStopId,departureSeconds,arrivalSeconds],i)=>({instanceId:'out',fromStopId,toStopId,departureSeconds,arrivalSeconds,fromSequence:i+1,toSequence:i+2}));
  p.transfers=[];
  const out=pruneUnreachable(p,{includeVisits:true});
  assert.deepEqual(out.segments,p.segments.slice(0,6));
  assert.deepEqual(out.places,p.places);
  const late=structuredClone(p);late.departureSeconds+=86400;late.deadlineSeconds+=86400;
  for(const s of late.segments){s.departureSeconds+=86400;s.arrivalSeconds+=86400;}
  assert.deepEqual(pruneUnreachable(late,{includeVisits:true}).segments,late.segments.slice(0,6));
});

test('visit-state pruning never removes an edge on any exhaustive relaxed path (80 generated networks)',()=>{
  let seed=12345;
  const random=n=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed%n;};
  for(let trial=0;trial<80;trial++) {
    const stopIds=['a','b','c','v0','v1','v2','d'];
    const visits=Array.from({length:trial%3===0?3:2},(_,i)=>({role:'visit',accessStops:[{stopId:'v'+i}],staySeconds:1+random(4)}));
    const fullMask=(1<<visits.length)-1;
    const p={...fixture(),departureSeconds:0,deadlineSeconds:30,places:[{role:'origin',accessStops:[{stopId:'a'}]},...visits,{role:'destination',accessStops:[{stopId:'d'}]}],transfers:trial%2?[{fromStopId:'b',toStopId:'c',transferType:3}]:[]};
    p.segments=Array.from({length:25},(_,i)=>{
      const departureSeconds=random(27);
      return {instanceId:'out',fromStopId:stopIds[random(stopIds.length)],toStopId:stopIds[random(stopIds.length)],fromSequence:i+1,toSequence:i+2,departureSeconds,arrivalSeconds:departureSeconds+1+random(3)};
    });
    const witness=[['a','v0',1,2],['v0','v1',9,10],...(visits.length===3?[['v1','v2',17,18],['v2','d',26,27]]:[['v1','d',26,27]])];
    for(const [fromStopId,toStopId,departureSeconds,arrivalSeconds] of witness) {const i=p.segments.length;p.segments.push({instanceId:'out',fromStopId,toStopId,fromSequence:i+1,toSequence:i+2,departureSeconds,arrivalSeconds});}
    const closure=s=>new Set(s==='b'&&p.transfers.length?['b','c']:[s]);
    const required=new Set(),memo=new Map();
    function canFinish(stop,mask,time) {
      const key=[stop,mask,time].join('/');if(memo.has(key))return memo.get(key);
      const connected=closure(stop);
      let feasible=mask===fullMask&&connected.has('d')&&time<=30;
      visits.forEach((v,bit)=>{if(!(mask&(1<<bit))&&connected.has(v.accessStops[0].stopId)&&time+v.staySeconds<=30)feasible=canFinish(v.accessStops[0].stopId,mask|(1<<bit),time+v.staySeconds)||feasible;});
      p.segments.forEach((s,i)=>{
        if(connected.has(s.fromStopId)&&s.departureSeconds>=time&&s.arrivalSeconds<=30&&canFinish(s.toStopId,mask,s.arrivalSeconds)){required.add(i);feasible=true;}
      });
      memo.set(key,feasible);return feasible;
    }
    canFinish('a',0,0);
    const retained=new Set(pruneUnreachable(p,{includeVisits:true}).segments.map(s=>s.fromSequence-1));
    for(const index of required)assert(retained.has(index),`trial ${trial}, required edge ${index}`);
    // Exact against relaxed reachability, stronger than the required legal-path superset.
    assert.deepEqual([...retained].sort((a,b)=>a-b),[...required].sort((a,b)=>a-b),`trial ${trial}`);
  }
});

test('cache key includes stay durations used by mandatory-visit pruning',()=>{
  const q={date:'2026-11-01',departureSeconds:0,deadlineSeconds:100,modes:['rail'],minimumTransferSeconds:300,origin:{accessStops:[{stopId:'a'}]},visits:[{accessStops:[{stopId:'v'}],staySeconds:30}],destination:{accessStops:[{stopId:'d'}]}};
  assert.notEqual(cacheKey('version',q,true),cacheKey('version',{...q,visits:[{...q.visits[0],staySeconds:60}]},true));
});
