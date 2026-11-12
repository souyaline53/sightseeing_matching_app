// Isolated demo project and loopback-only endpoints. Never targets production.
import assert from 'node:assert/strict';
const project = 'demo-tabisaki-visit';
const auth = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const db = `http://127.0.0.1:8080/v1/projects/${project}/databases/(default)/documents`;
async function request(url, token, body, method = 'POST') {
  const response = await fetch(url, {method, headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {})}, ...(body ? {body: JSON.stringify(body)} : {})});
  return {status: response.status, body: await response.json()};
}
async function login(email) {
  const result = await request(`${auth}/accounts:signUp?key=local`, null, {email, password: 'local-test-123', returnSecureToken: true});
  assert.equal(result.status, 200);
  return result.body;
}
function encode(value) {
  if (value === null) return {nullValue: null};
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encode)}};
  if (typeof value === 'object') return {mapValue: {fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, encode(v)]))}};
  if (typeof value === 'boolean') return {booleanValue: value};
  if (typeof value === 'number') return Number.isInteger(value) ? {integerValue: String(value)} : {doubleValue: value};
  return {stringValue: value};
}
function decode(value) {
  if ('nullValue' in value) return null;
  if ('arrayValue' in value) return (value.arrayValue.values ?? []).map(decode);
  if ('mapValue' in value) return Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(([k, v]) => [k, decode(v)]));
  if ('integerValue' in value) return Number(value.integerValue);
  return value.stringValue ?? value.booleanValue ?? value.doubleValue;
}
const base = {name: '検証用公園', title: '公園', area: '北海道', category: '自然', description: '紹介', story: '物語', surprise: '魅力', address: '札幌市', latitude: 43, longitude: 141, minutes: 60, accessMinutes: 10, order: 0, photo: '', photoPath: '', additionalPhotos: [], additionalPhotoPaths: [], accessStops: [], accessNotes: '保持'};
const info = {
  openingHoursStatus: 'scheduled',
  openingHours: Object.fromEntries(['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].map(d => [d, d === 'mon' ? [] : [{open: '09:00', close: '12:00'}, {open: '13:00', close: '17:00'}]])),
  specialHours: [{date: '2026-12-31', closed: true, hours: [], note: '年末休業'}],
  seasonalAvailability: {status: 'seasonal', periods: [{startMonth: 12, startDay: 1, endMonth: 3, endDay: 31}], custom: '保持'},
  recommendedSeasons: ['winter'], environmentType: 'mixed',
  admissionFee: {status: 'paid', adultYen: 800, childYen: null, note: '', custom: '保持'},
  reservationRequired: null, experienceTags: ['学び', '自然'], officialUrl: 'https://site.example.test',
};
async function commit(token, data, current) {
  const fields = {...encode(data).mapValue.fields, ...(current ? {createdAt: current.createdAt} : {})};
  return request(`${db}:commit`, token, {writes: [{update: {name: `projects/${project}/databases/(default)/documents/sightseeing_spot/visit-test`, fields}, updateTransforms: [...(!current ? [{fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME'}] : []), {fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME'}]}]});
}
let admin, other;
try {
  admin = await login('nichi-ka@nichi-ka.com');
  other = await login('visit-user@example.test');
  assert.equal((await commit(null, {...base, ...info})).status, 403);
  assert.equal((await commit(other.idToken, {...base, ...info})).status, 403);
  assert.equal((await commit(admin.idToken, {...base, ...info})).status, 403, 'unverified admin denied');
  assert.equal((await request(`${auth}/accounts:update?key=local`, 'owner', {localId: admin.localId, emailVerified: true})).status, 200);
  admin = {...admin, ...(await request(`${auth}/accounts:signInWithPassword?key=local`, null, {email: admin.email, password: 'local-test-123', returnSecureToken: true})).body};
  assert.equal((await commit(admin.idToken, base)).status, 200, 'legacy fields remain accepted');
  const legacy = (await request(`${db}/sightseeing_spot/visit-test`, null, null, 'GET')).body.fields;
  assert.equal((await commit(admin.idToken, {...base, ...info}, legacy)).status, 200, 'new metadata saved');
  const saved = (await request(`${db}/sightseeing_spot/visit-test`, null, null, 'GET')).body.fields;
  for (const [key, value] of Object.entries(info)) assert.deepEqual(decode(saved[key]), value, `${key} roundtrip`);
  assert.deepEqual(saved.createdAt, legacy.createdAt);
  assert.equal(saved.accessNotes.stringValue, '保持');
  for (const change of [{environmentType: 'invalid'}, {openingHoursStatus: 'invalid'}, {reservationRequired: 'true'}, {admissionFee: {status: 'paid', adultYen: -1}}, {officialUrl: 'http://example.test'}]) {
    assert.equal((await commit(admin.idToken, {...base, ...info, ...change}, saved)).status, 403, `reject ${JSON.stringify(change)}`);
  }
  const defaults = {...info, openingHoursStatus: 'unknown', openingHours: null, specialHours: [], seasonalAvailability: {status: 'unknown', periods: []}, recommendedSeasons: [], environmentType: 'unknown', admissionFee: {status: 'unknown', adultYen: null, childYen: null, note: ''}, experienceTags: [], officialUrl: ''};
  assert.equal((await commit(admin.idToken, {...base, ...defaults}, saved)).status, 200, 'default unknown metadata accepted');
  console.log('PASS: legacy + all new fields roundtrip, timestamps, admin authorization, invalid scalar types/statuses');
} finally {
  await request(`${db}/sightseeing_spot/visit-test`, 'owner', null, 'DELETE');
  for (const user of [admin, other].filter(Boolean)) await request(`${auth}/accounts:delete?key=local`, 'owner', {localId: user.localId});
}
