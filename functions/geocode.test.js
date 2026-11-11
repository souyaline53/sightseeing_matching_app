const { test } = require('node:test');
const assert = require('node:assert/strict');
const { geocodeAddress } = require('./geocode');
const auth = { token: { email: 'nichi-ka@nichi-ka.com', email_verified: true } };
test('geocode authorizes, rejects missing/ambiguous/unavailable results and preserves coordinate order', async () => {
  await assert.rejects(geocodeAddress({data:{address:'住所'}}), {code:'permission-denied'});
  await assert.rejects(geocodeAddress({auth,data:{address:''}}), {code:'invalid-argument'});
  const original = global.fetch;
  try {
    global.fetch = async url => {
      assert.equal(url.searchParams.get('q'), '北海道夕張市高松7番地');
      return { ok:true, json:async()=>[{geometry:{coordinates:[141.98732,43.065662]}}] };
    };
    const request = {auth,data:{address:'北海道夕張市高松7番地'}};
    assert.deepEqual(await geocodeAddress(request), {latitude:43.065662,longitude:141.98732});
    for (const results of [[], [{},{}]]) {
      global.fetch = async()=>({ok:true,json:async()=>results});
      await assert.rejects(geocodeAddress(request), {code:'not-found'});
    }
    global.fetch = async()=>{throw new Error('network');};
    await assert.rejects(geocodeAddress(request), {code:'unavailable'});
  } finally {global.fetch = original;}
});
