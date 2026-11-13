'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { optimizeTransportItinerary, validateTransportData, parseItinerary, limitTransportRequests } = require('./transport_dify');
const payload = require('../docs/transport_optimizer_meroad_coal_optimized.json');
const key = 'app-test-transport-secret-never-log';
const data = () => ({ transport_data: JSON.stringify(payload) });
const request = () => ({ auth: { uid: 'firebase-user' }, data: data() });
function database() {
  let state, writes = 0, tail = Promise.resolve();
  return { collection: (name) => { assert.equal(name, '_transport_optimizer_request_limits'); return { doc: (id) => { assert.match(id, /^[a-f0-9]{64}$/); return { id }; } }; },
    runTransaction: (action) => {
      const result = tail.then(() => action({ get: async () => ({ data: () => state }), set: (_, value) => { state = value; writes++; } }));
      tail = result.catch(() => {}); return result;
    }, get writes() { return writes; } };
}
const itinerary = { status: 'feasible', candidateId: 'candidate_001', visits: [{ spotId: 'coal', staySeconds: 5400 }], legs: [{ routeId: 'registered-route' }], requiresReview: true, warnings: ['未確認情報あり'] };
const response = (outputs = { recommendation: true, itinerary_json: JSON.stringify(itinerary), message: key }) => ({ data: { status: 'succeeded', outputs } });
test('sends transport_data object once with bound secret and pseudonymous UID; returns entire Code ④ itinerary', async () => {
  let calls = 0;
  const result = await optimizeTransportItinerary(request(), database(), () => key, { fetch: async (url, options) => {
    calls++; assert.equal(url, 'https://api.dify.ai/v1/workflows/run'); assert.equal(options.method, 'POST'); assert.equal(options.redirect, 'error');
    assert.equal(options.headers.Authorization, `Bearer ${key}`);
    const body = JSON.parse(options.body); assert.equal(body.response_mode, 'blocking'); assert.match(body.user, /^[a-f0-9]{64}$/); assert.notEqual(body.user, 'firebase-user');
    assert.deepEqual(Object.keys(body.inputs), ['transport_data']); assert.equal(typeof body.inputs.transport_data, 'object'); assert.deepEqual(body.inputs.transport_data, payload);
    return Response.json(response({ recommendation: true, itinerary_json: JSON.stringify(itinerary), message: '成功: 3222文字' }));
  } });
  assert.equal(calls, 1); assert.deepEqual(result, { success: true, itinerary, message: '旅程生成成功' });
});
test('accepts success alias, consistent dual flags, false result; rejects contradictory/malformed output', () => {
  for (const flag of [{ success: true }, { recommendation: true, success: true }]) assert.deepEqual(parseItinerary(response({ ...flag, itinerary_json: JSON.stringify(itinerary) })).itinerary, itinerary);
  assert.equal(parseItinerary(response({ success: false, itinerary_json: '{"status":"infeasible","reason":"no route"}' })).success, false);
  for (const outputs of [{}, { success: 'true', itinerary_json: '{}' }, { success: true, recommendation: false, itinerary_json: '{}' }, { success: true, itinerary_json: 'bad' }, { success: true, itinerary_json: '[]' }, { success: true, itinerary_json: '{}' }]) assert.throws(() => parseItinerary(response(outputs)), (e) => e.code === 'internal');
  for (const status of ['failed', 'running', 'stopped']) assert.throws(() => parseItinerary({ data: { status, outputs: response().data.outputs } }), (e) => e.code === 'internal');
});
test('unauthenticated and invalid inputs cannot read key, charge limiter or call Dify', async () => {
  const fail = () => assert.fail('must not execute');
  await assert.rejects(() => optimizeTransportItinerary({ data: data() }, {}, fail, { fetch: fail }), (e) => e.code === 'unauthenticated');
  for (const invalid of [null, {}, { transport_data: payload }, { transport_data: 'bad' }, { transport_data: '[]' }, { transport_data: '{}' }, { ...data(), uid: 'spoof' }]) {
    await assert.rejects(() => optimizeTransportItinerary({ auth: { uid: 'user' }, data: invalid }, {}, fail, { fetch: fail }), (e) => e.code === 'invalid-argument');
  }
});
test('rejects invalid schema references, time fields, places, openings and preserved transfer constraints', () => {
  for (const edit of [p => p.schemaVersion = 2, p => p.segments[0].instanceId = 'missing', p => p.segments[0].pickup = 'true', p => p.segments[0].arrivalSeconds = -1, p => p.stops.push(p.stops[0]), p => p.places[1].opening.windows = [], p => p.places[1].accessStops[0].seconds = -5, p => p.instances[0].routeId = 'missing', p => p.transfers[0].transferType = 99]) {
    const p = structuredClone(payload); edit(p); assert.throws(() => validateTransportData({ transport_data: JSON.stringify(p) }), (e) => e.code === 'invalid-argument');
  }
});
test('hundreds-of-thousands of characters fit Callable envelope; character and byte caps reject without truncation', () => {
  const input = data(); const parsed = validateTransportData(input);
  assert(parsed.characters > 300000); assert(parsed.bytes < 500000);
  assert(Buffer.byteLength(JSON.stringify({ data: input })) < 1024 * 1024);
  assert.throws(() => validateTransportData({ transport_data: 'x'.repeat(4000001) }), (e) => e.code === 'resource-exhausted');
  const p = structuredClone(payload); p.warnings = ['x'.repeat(4100000)]; const original = JSON.stringify(p);
  assert.throws(() => validateTransportData({ transport_data: original }), (e) => e.code === 'resource-exhausted');
  assert.equal(JSON.stringify(p), original);
});
test('transactional UID limit allows 3/minute, no Dify retry; new window resets', async () => {
  const db = database();
  const results = await Promise.allSettled(Array.from({ length: 4 }, () => limitTransportRequests(db, 'same-user', 1000)));
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 3);
  assert.equal(results.find((r) => r.status === 'rejected').reason.code, 'resource-exhausted');
  assert.equal(db.writes, 3); await limitTransportRequests(db, 'same-user', 61000); assert.equal(db.writes, 4);
});
test('HTTP status, bad JSON and workflow failures are sanitized and requested exactly once', async () => {
  for (const [status, code] of [[401, 'failed-precondition'], [403, 'failed-precondition'], [429, 'resource-exhausted'], [500, 'unavailable']]) {
    let calls = 0;
    await assert.rejects(() => optimizeTransportItinerary(request(), database(), () => key, { fetch: async () => { calls++; return new Response(key, { status }); } }), (e) => e.code === code && !e.message.includes(key));
    assert.equal(calls, 1);
  }
  for (const body of ['not json', JSON.stringify({ data: { status: 'failed', error: key } }), JSON.stringify(response())]) {
    await assert.rejects(() => optimizeTransportItinerary(request(), database(), () => key, { fetch: async () => new Response(body) }), (e) => e.code === 'internal' && !JSON.stringify(e).includes(key));
  }
});
test('timeout, network and missing secret errors are safe; failed attempts consume limiter', async () => {
  let calls = 0; const db = database();
  await assert.rejects(() => optimizeTransportItinerary(request(), db, () => key, { timeoutMs: 5, fetch: async (_, { signal }) => {
    calls++; return new Promise((_, reject) => { const timer = setTimeout(() => reject(Error('unexpected')), 100); signal.addEventListener('abort', () => { clearTimeout(timer); reject(signal.reason); }, { once: true }); });
  } }), (e) => e.code === 'deadline-exceeded');
  assert.equal(calls, 1); assert.equal(db.writes, 1);
  await assert.rejects(() => optimizeTransportItinerary(request(), database(), () => key, { fetch: async () => { throw Error(key); } }), (e) => e.code === 'unavailable' && !e.message.includes(key));
  for (const read of [() => '', () => { throw Error(key); }]) await assert.rejects(() => optimizeTransportItinerary(request(), database(), read), (e) => e.code === 'failed-precondition' && !e.message.includes(key));
});
test('response cap and escaped secret reflection never expose upstream contents', async () => {
  for (const body of ['x'.repeat(1000001), JSON.stringify(response()).replaceAll('app-', '\\u0061pp-')]) {
    await assert.rejects(() => optimizeTransportItinerary(request(), database(), () => key, { fetch: async () => new Response(body) }), (e) => e.code === 'internal' && !JSON.stringify(e).includes(key));
  }
});
test('Gen2 export binds only transport Secret and preserves existing Callable exports', () => {
  const functions = require('./index');
  const e = functions.optimizeTransportItinerary.__endpoint;
  assert.equal(e.platform, 'gcfv2'); assert.deepEqual(e.region, ['asia-northeast1']);
  assert.equal(e.concurrency, 1); assert.equal(e.maxInstances, 2); assert.equal(e.timeoutSeconds, 120);
  assert.deepEqual(e.secretEnvironmentVariables.map((s) => s.key), ['DIFY_TRANSPORT_API_KEY']);
  for (const name of ['getAiRecommendations', 'prepareTransportOptimization', 'searchTransportJourneys', 'importTransport', 'saveManualTransport']) assert.equal(typeof functions[name], 'function');
  assert.deepEqual(functions.getAiRecommendations.__endpoint.secretEnvironmentVariables.map((s) => s.key), ['DIFY_API_KEY']);
});
test('HTTP errors and workflow outputs never write keys or network JSON to console', async () => {
  const entries = [], originals = Object.fromEntries(['log', 'info', 'warn', 'error'].map((k) => [k, console[k]]));
  try {
    for (const k of Object.keys(originals)) console[k] = (...args) => entries.push(args);
    await assert.rejects(() => optimizeTransportItinerary(request(), database(), () => key, { fetch: async () => new Response(key, { status: 500 }) }));
    await optimizeTransportItinerary(request(), database(), () => key, { fetch: async () => Response.json(response({ success: true, itinerary_json: JSON.stringify(itinerary), message: 'ok' })) });
    assert.deepEqual(entries, []);
  } finally { Object.assign(console, originals); }
});

test('accepts network above former character/byte caps, preserving all segments and transfers', async () => {
  const p = structuredClone(payload); p.auditNote = 'x'.repeat(3000000);
  const original = JSON.stringify(p);
  assert(original.length > 399999); assert(Buffer.byteLength(original) > 500000);
  const validated = validateTransportData({ transport_data: original });
  assert.equal(validated.json, original);
  let calls = 0;
  await optimizeTransportItinerary({ ...request(), data: { transport_data: original } }, database(), () => key, {fetch: async (_url, options) => {
    calls++; assert.deepEqual(JSON.parse(options.body).inputs.transport_data, p);
    return Response.json(response({ success: true, itinerary_json: JSON.stringify(itinerary) }));
  }});
  assert.equal(calls, 1);
});
test('size and minute limits have separate safe reasons and measurements', async () => {
  const p = structuredClone(payload); p.auditNote = 'x'.repeat(2100000);
  const old = process.env.DIFY_TRANSPORT_MAX_CHARACTERS;
  try { process.env.DIFY_TRANSPORT_MAX_CHARACTERS='2000000';
    assert.throws(() => validateTransportData({transport_data: JSON.stringify(p)}), e => e.code === 'resource-exhausted' && e.details.reason === 'transport-payload-too-large' && e.details.characters > e.details.maxCharacters && e.details.difyRequestStarted === false);
  } finally { if(old===undefined)delete process.env.DIFY_TRANSPORT_MAX_CHARACTERS;else process.env.DIFY_TRANSPORT_MAX_CHARACTERS=old; }
  assert.throws(() => validateTransportData({transport_data: 'x'.repeat(4000001)}), e => e.details.reason === 'transport-payload-too-large' && e.details.bytes === 4000001);
  const db = database(); await limitTransportRequests(db,'u',1000); await limitTransportRequests(db,'u',1001); await limitTransportRequests(db,'u',1002);
  await assert.rejects(limitTransportRequests(db,'u',2000), e => e.details.reason === 'ai-minute-limit' && e.details.retryAfterSeconds === 59);
});
test('environment size limits apply to validator and serializer consistently', () => {
  const old = process.env.DIFY_TRANSPORT_MAX_BYTES;
  try {
    process.env.DIFY_TRANSPORT_MAX_BYTES = '100';
    assert.throws(() => validateTransportData(data()), e => e.details.maxBytes === 100);
  } finally { if (old === undefined) delete process.env.DIFY_TRANSPORT_MAX_BYTES; else process.env.DIFY_TRANSPORT_MAX_BYTES = old; }
});

test('explicit string compatibility is supported without changing the Callable input', async () => {
  const previous=process.env.DIFY_TRANSPORT_INPUT_TYPE;
  try {
    process.env.DIFY_TRANSPORT_INPUT_TYPE='string';
    let calls=0;
    await optimizeTransportItinerary(request(),database(),()=>key,{fetch:async(_url,options)=>{
      calls++;const input=JSON.parse(options.body).inputs.transport_data;
      assert.equal(typeof input,'string');assert.deepEqual(JSON.parse(input),payload);
      return Response.json(response({success:true,itinerary_json:JSON.stringify(itinerary)}));
    }});assert.equal(calls,1);
  } finally {if(previous===undefined)delete process.env.DIFY_TRANSPORT_INPUT_TYPE;else process.env.DIFY_TRANSPORT_INPUT_TYPE=previous;}
});
test('Dify HTTP failure exposes only safe status metadata; no error body or retry', async () => {
  for (const status of [400,401,403,413,429,500]) {
    let calls=0;
    await assert.rejects(optimizeTransportItinerary(request(),database(),()=>key,{fetch:async()=>{calls++;return new Response(key,{status});}}), e=>e.details.httpStatus===status&&!JSON.stringify(e).includes(key));
    assert.equal(calls,1);
  }
});
