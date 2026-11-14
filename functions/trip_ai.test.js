'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { registerAiTrip, optimizeTripTransport } = require('./trip_ai');
const payload = require('../docs/transport_optimizer_meroad_coal_optimized.json');
const trip = (id = 'trip-original', ai = {}) => ({ id, ai, title: 'テスト', saved: [], stops: [{ id: 'melon' }, { id: 'coal' }] });
function database() {
  const rows = new Map(); let tail = Promise.resolve();
  const ref = (path) => ({ path, get: async () => snapshot(path), update: async (v) => { assert(rows.has(path)); rows.set(path, { ...rows.get(path), ...structuredClone(v) }); } });
  const snapshot = (path) => ({ exists: rows.has(path), data: () => structuredClone(rows.get(path)) });
  return { rows, doc: ref, runTransaction(action) { const next = tail.then(async () => {
    const writes = [];
    const result = await action({ get: async (r) => snapshot(r.path), set: (r, v) => writes.push([r.path, v]), create: (r,v) => { assert(!rows.has(r.path)); writes.push([r.path, v]); }, update: (r, v) => { assert(rows.has(r.path)); writes.push([r.path, {...rows.get(r.path), ...v}]); } });
    for (const [p,v] of writes) rows.set(p, structuredClone(v)); return result;
  }); tail = next.catch(() => {}); return next; } };
}
async function setup() { const db = database(); const { tripId } = await registerAiTrip({auth:{uid:'u'}, data:{trip:trip()}},db); return {db, tripId, ref: db.doc(`users/u/ai_trips/${tripId}`)}; }
const request = (tripId, requestId = 'request-one') => ({auth:{uid:'u'},data:{tripId,requestId,transport_data:JSON.stringify(payload)}});
const result = () => ({success:true,itinerary:{status:'feasible',visitOrder:['melon','coal'],legs:[],requiresReview:true},message:'成功'});
const run = async (_r,_db,_key, hooks) => { await hooks.onDispatch(); return result(); };
test('requires auth and own server-issued trip; cannot call with arbitrary trip IDs', async () => {
  const {db, tripId} = await setup();
  await assert.rejects(registerAiTrip({data:{trip:trip()}},db),e=>e.code==='unauthenticated');
  await assert.rejects(optimizeTripTransport({auth:{uid:'other'},data:{tripId,requestId:'x'}},db,null,()=>''),e=>e.code==='permission-denied');
  await assert.rejects(optimizeTripTransport({auth:{uid:'u'},data:{}},db,null,()=>''),e=>e.code==='invalid-argument');
});
test('duplicate and changed local IDs preserve server root and quota; alias cannot switch roots', async()=>{
  const {db,tripId} = await setup();
  const copy = await registerAiTrip({auth:{uid:'u'},data:{trip:trip('copy',{lineage:'trip-original'})}},db);
  assert.equal(copy.tripId,tripId);
  const other = await registerAiTrip({auth:{uid:'u'},data:{trip:trip('separate')}},db);
  assert.notEqual(other.tripId,tripId);
  assert.equal((await registerAiTrip({auth:{uid:'u'},data:{trip:trip(),rootId:other.tripId}},db)).tripId,tripId);
});
test('concurrent requests dispatch once; retries return their result and new requests can regenerate',async()=>{
  const {db,tripId,ref} = await setup(); let calls=0;
  const options={run: async(...args)=>{calls++; return run(...args);}};
  const both=await Promise.allSettled([optimizeTripTransport(request(tripId),db,null,()=> 'test',options),optimizeTripTransport(request(tripId,'request-two'),db,null,()=> 'test',options)]);
  assert.equal(calls,1); assert(both.some(r=>r.status==='fulfilled'));
  const cached=await optimizeTripTransport(request(tripId,'request-one'),db,null,()=>{throw Error('must not read');},{run:()=>assert.fail('no dispatch')});
  assert.equal(cached.itinerary.status,'feasible'); assert.equal((await ref.get()).data().aiGenerationStatus,'completed');
  assert.equal(typeof (await ref.get()).data().aiResult,'string');
  await optimizeTripTransport(request(tripId,'request-three'),db,null,()=> 'test',options);
  assert.equal(calls,2);
  assert.equal((await ref.get()).data().aiGenerationRequestId,'request-three');
  // Replaying an older successful request must never dispatch again.
  await optimizeTripTransport(request(tripId,'request-one'),db,null,()=>assert.fail('no key'),{run:()=>assert.fail('no dispatch')});
  assert.equal(calls,2);
});
test('a timeout after dispatch remains uncertain and cannot be retried',async()=>{
  const {db,tripId,ref}=await setup();let calls=0;
  await assert.rejects(optimizeTripTransport(request(tripId),db,null,()=> 'test',{run:async(_a,_b,_c,h)=>{calls++;await h.onDispatch();throw Error('secret');}}),e=>e.code==='unavailable'&&!e.message.includes('secret'));
  assert.equal((await ref.get()).data().aiGenerationStatus,'uncertain');
  await assert.rejects(optimizeTripTransport(request(tripId),db,null,()=> 'test',{run}),e=>e.code==='already-exists');assert.equal(calls,1);
});
test('pre-dispatch failure is retryable; infeasible retains a retryable failed state',async()=>{
  const {db,tripId,ref}=await setup();
  await assert.rejects(optimizeTripTransport(request(tripId),db,null,()=> 'test',{run:async()=>{throw Error();}}));
  assert.equal((await ref.get()).data().aiGenerationStatus,'failed');
  const no = await optimizeTripTransport(request(tripId,'r2'),db,null,()=> 'test',{run:async(_a,_b,_c,h)=>{await h.onDispatch();return {success:true,itinerary:{status:'infeasible'},message:'no'};}});
  assert.equal(no.success,false);assert.equal((await ref.get()).data().aiGenerationStatus,'failed');
  await optimizeTripTransport(request(tripId,'r3'),db,null,()=> 'test',{run});
});
test('stale undispatched lease can recover; dispatched lease never expires',async()=>{
  const {db,tripId,ref}=await setup();
  await ref.update({aiGenerationStatus:'processing',aiGenerationStartedAt:0,aiGenerationPhase:'reserved',aiGenerationRequestId:'old',aiLeaseId:'old'});
  await optimizeTripTransport(request(tripId),db,null,()=> 'test',{run});
  const other=await setup();await other.ref.update({aiGenerationStatus:'processing',aiGenerationStartedAt:0,aiGenerationPhase:'dispatched'});
  await assert.rejects(optimizeTripTransport(request(other.tripId),other.db,null,()=> 'test',{run}),e=>e.code==='already-exists');
});
test('known workflow failure can retry, changed visits do not dispatch, daily cap applies across trips',async()=>{
  const {db,tripId,ref}=await setup();
  await assert.rejects(optimizeTripTransport(request(tripId),db,null,()=> 'test',{run:async(_a,_b,_c,h)=>{await h.onDispatch();await h.onWorkflowResponse({data:{status:'failed'}});throw Error();}}));
  assert.equal((await ref.get()).data().aiGenerationStatus,'failed');
  await ref.update({currentTrip:JSON.stringify({...trip(),stops:[{id:'other'}]})});
  await assert.rejects(optimizeTripTransport(request(tripId),db,null,()=> 'test',{run}),e=>e.code==='failed-precondition');
  await ref.update({currentTrip:JSON.stringify(trip())});
  const key=[...db.rows.keys()].find(k=>k.startsWith('_ai_trip_daily_limits/')); db.rows.set(key,{count:10});
  await assert.rejects(optimizeTripTransport(request(tripId),db,null,()=> 'test',{run}),e=>e.code==='resource-exhausted' && e.details.reason === 'ai-daily-limit');
});
test('expired reservation recovery cannot let the old worker dispatch or overwrite a newer success',async()=>{
  const {db,tripId,ref}=await setup();let release, entered; const started=new Promise(r=>entered=r);const wait=new Promise(r=>release=r);let sends=0;
  const old=optimizeTripTransport(request(tripId),db,null,()=> 'test',{run:async(_a,_b,_c,h)=>{entered();await wait;await h.onDispatch();sends++;return result();}});
  await started;await ref.update({aiGenerationStartedAt:0});
  const recovered=await registerAiTrip({auth:{uid:'u'},data:{trip:trip(),rootId:tripId}},db);assert.equal(recovered.aiGenerationStatus,'failed');
  await optimizeTripTransport(request(tripId,'new'),db,null,()=> 'test',{run:async(...args)=>{sends++;return run(...args);}});
  release();await assert.rejects(old);assert.equal(sends,1);assert.equal((await ref.get()).data().aiGenerationStatus,'completed');
});

test('preparation size failure does not reserve the trip, consume daily quota or dispatch Dify',async()=>{
  const {db,tripId,ref}=await setup();
  const {HttpsError}=require('firebase-functions/v2/https');
  const r=request(tripId);delete r.data.transport_data;r.data.input={};
  await assert.rejects(optimizeTripTransport(r,db,null,()=>assert.fail('no key'),{
    prepare:async()=>{throw new HttpsError('resource-exhausted','too large',{reason:'transport-payload-too-large',bytes:5000000,maxBytes:4000000,difyRequestStarted:false});},
    run:()=>assert.fail('must not dispatch'),
  }), e=>e.details.reason==='transport-payload-too-large');
  assert.equal((await ref.get()).data().aiGenerationStatus,'unused');
  assert.equal([...db.rows.keys()].filter(k=>k.startsWith('_ai_trip_daily_limits/')).length,0);
});

test('assumed opening and unverified registered walks are preserved as review reasons in the saved result',async()=>{
  const {db,tripId,ref}=await setup();
  const network=structuredClone(payload);
  network.places[1].opening={status:'known',windows:[[0,86400]],assumedOpen:true};
  network.places[1].accessStops[0].requiresReview=true;
  const req=request(tripId);req.data.transport_data=JSON.stringify(network);
  const response=await optimizeTripTransport(req,db,null,()=> 'test',{
    run:async(_a,_b,_c,h)=>{await h.onDispatch();return {...result(),itinerary:{...result().itinerary,requiresReview:false}};},
  });
  assert.equal(response.itinerary.requiresReview,true);
  assert(response.itinerary.reviewReasons.some(r=>r.includes('営業時間未確認')));
  assert(response.itinerary.reviewReasons.some(r=>r.includes('徒歩接続')));
  assert.deepEqual(JSON.parse((await ref.get()).data().aiResult).itinerary.reviewReasons,response.itinerary.reviewReasons);
});

test('car itinerary cannot dispatch AI transport optimization', async () => {
  const {db, tripId, ref} = await setup();
  const current = JSON.parse((await ref.get()).data().currentTrip);
  current.conditions = { transport: 1 };
  await ref.update({ currentTrip: JSON.stringify(current) });
  await assert.rejects(optimizeTripTransport(request(tripId), db, null,
    () => assert.fail('car must not read the AI key'),
    { run: () => assert.fail('car must not call AI') }),
    e => e.code === 'failed-precondition' && e.message === '車での移動はAIルート検索に対応していません。');
});
