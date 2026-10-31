// Emulator-only integration test; never reaches production or reads login credentials.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
if(!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST??'')) throw new Error('Local emulator required');
const root=`http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/sightseeing-matching-prototype/databases/(default)/documents`;
async function request(url,options={}) {
 const response=await fetch(url,{...options,headers:{Authorization:'Bearer owner','Content-Type':'application/json'}});
 assert.equal(response.status,200);return response.json();
}
for(const [collection,ids] of [['transit',['old_a','old_b']],['sightseeing_spot',['melon','lake','rail']]]) {
 for(const id of ids) await request(`${root}/${collection}?documentId=${id}`,{method:'POST',body:JSON.stringify({fields:{title:{stringValue:`検証用${id}`},note:{stringValue:'既存フィールドを維持'}}})});
}
function apply() {return execFileSync(process.execPath,['tool/replace_transport_samples.mjs','--emulator','--apply','--spot-ids=melon,lake,rail'],{encoding:'utf8'});}
apply();
assert.equal(((await request(`${root}/transit`)).documents??[]).length,0);
const trips=(await request(`${root}/transport_trips`)).documents;
assert.equal(trips.length,3);
for(const d of trips) assert.equal(d.fields.verificationStatus.stringValue,'sample');
assert.equal(trips.find(d=>d.name.endsWith('/sample_trip_2')).fields.stopTimes.arrayValue.values[0].mapValue.fields.departureMinutes.integerValue,'1510');
for(const id of ['melon','lake','rail']) {
 const doc=await request(`${root}/sightseeing_spot/${id}`);
 assert.equal(doc.fields.note.stringValue,'既存フィールドを維持');
 const access=doc.fields.accessStops.arrayValue.values;
 assert.equal(access.length,1);assert.equal(access[0].mapValue.fields.walkingMinutes.nullValue,null);
}
apply(); // Retry updates sample records without duplicating accessStops.
assert.equal((await request(`${root}/sightseeing_spot/melon`)).fields.accessStops.arrayValue.values.length,1);
// Real masters with the same ID must never be overwritten; no partial legacy deletion.
await request(`${root}/transport_routes/sample_route?updateMask.fieldPaths=sourceType`,{method:'PATCH',body:JSON.stringify({fields:{sourceType:{stringValue:'manual'}}})});
assert.throws(apply);
console.log('PASS: legacy deletion, exactly 3 sample trips, unknown walking, preserved spot fields, retry safety, non-sample collision guard');
