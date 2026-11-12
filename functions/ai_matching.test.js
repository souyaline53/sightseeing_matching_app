const test = require('node:test');
const assert = require('node:assert/strict');
const {serializeSpot, validateInput, loadCandidates, rateLimit, parseRecommendations, getAiRecommendations} = require('./ai_matching');
function database(total = 40) {
  const records = Array.from({length: total}, (_, i) => ({id: `spot-${String(i).padStart(3, '0')}`, data: () => ({name: '公園', photo: 'private-photo'})}));
  const limits = new Map();
  let reads = 0;
  return {
    get reads() { return reads; },
    collection(name) {
      if (name === '_ai_request_limits') return {doc: id => ({id})};
      assert.equal(name, 'sightseeing_spot');
      const query = (start = 0, size = total) => ({
        orderBy() { return this; }, select(...fields) { assert(!fields.includes('photo')); return this; },
        offset(n) { return query(n, size); }, limit(n) { return query(start, n); },
        async get() { reads++; return {docs: records.slice(start, start + size)}; },
        count() { return {get: async () => ({data: () => ({count: total})})}; },
      });
      return query();
    },
    async runTransaction(fn) { return fn({get: async doc => ({data: () => limits.get(doc.id)}), set: (doc, data) => limits.set(doc.id, data)}); },
  };
}
const request = {auth: {uid: 'anonymous-user', token: {firebase: {sign_in_provider: 'anonymous'}}}, data: {interests: '自然', mood: '癒やし'}};
const response = recommendations => new Response(JSON.stringify({data: {status: 'succeeded', outputs: {recommendations: {recommendations}}}}));
test('all new metadata defaults are unknown/null, photos and arbitrary metadata omitted', () => {
  const spot = serializeSpot({id: 'legacy', data: () => ({photo: 'secret', minutes: '60', admissionFee: {note: 'test', email: 'private'}})});
  assert.equal(spot.openingHours, null); assert.equal(spot.openingHoursStatus, 'unknown');
  assert.equal(spot.admissionFee.status, 'unknown'); assert.equal(spot.admissionFee.adultYen, null);
  assert.equal(spot.minutes, null); assert.equal(spot.reservationRequired, null);
  assert(!JSON.stringify(spot).includes('private')); assert(!('photo' in spot));
  const rich = serializeSpot({id: 'a', data: () => ({openingHoursStatus: 'scheduled', openingHours: {mon: []}, specialHours: [{date: '2026-12-31', closed: true, hours: []}], seasonalAvailability: {status: 'seasonal', periods: [{startMonth: 12, startDay: 1, endMonth: 3, endDay: 31}]}, admissionFee: {status: 'free', adultYen: 0}, latitude: 43, accessStops: [{stopId: 'stop', walkingMinutes: 10}]})});
  assert.deepEqual(rich.openingHours.mon, []); assert.equal(rich.openingHours.tue, null);
  assert.equal(rich.specialHours[0].closed, true); assert.equal(rich.seasonalAvailability.periods[0].endMonth, 3);
  assert.equal(rich.admissionFee.adultYen, 0); assert.equal(rich.accessStops[0].walkingMinutes, 10);
});
test('random bounded circular windows can include every document without evaluation', async () => {
  const db = database();
  const a = await loadCandidates(db, () => 0), b = await loadCandidates(db, () => 35);
  assert.equal(a.length, 30); assert.equal(b.length, 30); assert.equal(b[0].id, 'spot-035');
  assert.equal(new Set(b.map(x => x.id)).size, 30); assert.notDeepEqual(a, b);
  assert.equal((await loadCandidates(database(0))).length, 0);
  assert.equal((await loadCandidates(database(3))).length, 3);
});
test('legacy inputs retained; optional context whitelist protects profile fields', () => {
  assert.deepEqual(validateInput(request.data), request.data);
  const input = validateInput({...request.data, travelContext: {budgetYen: 8000, savedSpotIds: ['a', 'a'], email: 'private'}});
  assert.deepEqual(JSON.parse(input.mood), {mood: '癒やし', travelContext: {budgetYen: 8000, savedSpotIds: ['a'], timeZone: 'Asia/Tokyo'}});
  for (const change of [{mood: ''}, {interests: 'x'.repeat(501)}, {travelContext: {budgetYen: -1}}, {travelContext: {savedSpotIds: ['x', 1]}}, {travelContext: []}]) assert.throws(() => validateInput({...request.data, ...change}), {code: 'invalid-argument'});
});
test('output validation only drops invalid records, preserves Dify order and caps at ten', () => {
  const spots = Array.from({length: 15}, (_, i) => ({id: `s${i}`}));
  const recs = [{spot_id: 'invalid', reason: ''}, {spot_id: 's2', reason: 3}, {spot_id: 's2', reason: 'valid'}, {spot_id: 's2', reason: 'duplicate'}, ...spots.map(s => ({spot_id: s.id, reason: '理由'}))];
  const payload = {data: {status: 'succeeded', outputs: {recommendations: JSON.stringify({recommendations: recs})}}};
  const parsed = parseRecommendations(payload, spots);
  assert.equal(parsed.length, 10); assert.deepEqual(parsed.slice(0, 3).map(r => r.spot_id), ['s2', 's0', 's1']);
  for (const bad of [null, {data: {status: 'failed'}}, {data: {status: 'succeeded', outputs: {recommendations: 'bad'}}}, {data: {status: 'succeeded', outputs: {recommendations: {recommendations: [{spot_id: 'missing', reason: ''}]}}}}]) assert.throws(() => parseRecommendations(bad, spots), {code: 'internal'});
});
test('authentication, durable quota and quota expiry', async () => {
  const db = database();
  await assert.rejects(getAiRecommendations({data: request.data}, db, 'key'), {code: 'unauthenticated'});
  assert.equal(db.reads, 0);
  for (let i = 0; i < 6; i++) await rateLimit(db, 'uid', 1000);
  await assert.rejects(rateLimit(db, 'uid', 1001), {code: 'resource-exhausted'});
  await rateLimit(db, 'uid', 61000);
  await rateLimit(db, 'other', 1001);
});
test('full call sends only three inputs, hashes uid and forwards unchanged Dify order', async () => {
  const db = database(3);
  let calls = 0;
  const result = await getAiRecommendations({...request, data: {...request.data, travelContext: {budgetYen: 8000}}}, db, 'test-key', {fetch: async (url, options) => {
    calls++;
    assert.equal(url, 'https://api.dify.ai/v1/workflows/run');
    assert.equal(options.headers.Authorization, 'Bearer test-key');
    const body = JSON.parse(options.body);
    assert.deepEqual(Object.keys(body.inputs).sort(), ['interests', 'mood', 'spots']);
    assert.notEqual(body.user, request.auth.uid);
    assert.equal(JSON.parse(body.inputs.spots).length, 3);
    assert(!body.inputs.spots.includes('photo'));
    return response([{spot_id: 'spot-002', reason: '先'}, {spot_id: 'spot-000', reason: '後'}]);
  }});
  assert.equal(calls, 1); assert.deepEqual(result.recommendations.map(r => r.spot_id), ['spot-002', 'spot-000']);
});
test('network, timeout, HTTP, invalid JSON and empty catalog are safe', async () => {
  for (const [fetch, code] of [
    [async () => { throw new Error('secret should not leak'); }, 'unavailable'],
    [async () => { throw new DOMException('timeout', 'TimeoutError'); }, 'deadline-exceeded'],
    [async () => new Response('secret', {status: 500}), 'unavailable'],
    [async () => new Response('invalid'), 'internal'],
    [async () => new Response('x'.repeat(1000001)), 'internal'],
  ]) await assert.rejects(getAiRecommendations(request, database(3), 'key', {fetch}), {code});
  assert.deepEqual(await getAiRecommendations(request, database(0), 'key', {fetch: () => assert.fail('must not call Dify')}), {recommendations: []});
});
