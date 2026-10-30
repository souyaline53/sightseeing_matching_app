const test = require('node:test');
const assert = require('node:assert/strict');
const { promoteMunicipality } = require('./municipality');

const admin = { uid: 'admin', token: { email: 'nichi-ka@nichi-ka.com', email_verified: true } };
const request = (auth = admin, email = 'municipality@example.test') => ({ auth, data: { email } });

test('role changes reject guests, ordinary users and unverified administrators before looking up email', async () => {
  const lookup = { getUserByEmail() { assert.fail('Unauthorized user must not look up accounts'); } };
  await assert.rejects(promoteMunicipality(request(null), lookup), { code: 'unauthenticated' });
  await assert.rejects(promoteMunicipality(request({ token: { email: 'other@example.test', email_verified: true } }), lookup), { code: 'permission-denied' });
  await assert.rejects(promoteMunicipality(request({ ...admin, token: { ...admin.token, email_verified: false } }), lookup), { code: 'permission-denied' });
});

test('administrator must provide a valid email and an existing registered account', async () => {
  await assert.rejects(promoteMunicipality(request(admin, ''), {}), { code: 'invalid-argument' });
  await assert.rejects(promoteMunicipality(request(), { getUserByEmail() { throw { code: 'auth/user-not-found' }; } }), { code: 'not-found', details: { reason: 'user-not-found' } });
});

test('promotion changes only the role and public chat fields, retaining private profile data', async () => {
  const writes = [];
  const account = { uid: 'municipality-uid', disabled: false };
  const auth = { async getUserByEmail(email) { assert.equal(email, 'municipality@example.test'); return account; } };
  const profile = { nickname: '観光案内', ageGroup: '30代', municipality: '札幌市', createdAt: 'original' };
  const db = {
    collection(collection) { return { doc(id) { return `${collection}/${id}`; } }; },
    async runTransaction(fn) {
      return fn({
        async get(path) { assert.equal(path, 'users/municipality-uid'); return { exists: true, data: () => profile }; },
        update(path, data) { writes.push({ path, data }); },
        set(path, data) { writes.push({ path, data }); },
      });
    },
  };
  const result = await promoteMunicipality(request(admin, ' municipality@example.test '), auth, db);
  assert.deepEqual(result, { uid: account.uid, displayName: '観光案内', userType: 'municipality' });
  assert.deepEqual(Object.keys(writes[0].data).sort(), ['updatedAt', 'userType']);
  assert.equal(writes[0].data.userType, 'municipality');
  assert.equal(writes[1].path, 'public_profiles/municipality-uid');
  assert.deepEqual(Object.keys(writes[1].data).sort(), ['displayName', 'uid', 'updatedAt', 'userType']);
  assert.equal(profile.createdAt, 'original');
});

test('incomplete or disabled accounts cannot be promoted', async () => {
  const auth = { async getUserByEmail() { return { uid: 'pending' }; } };
  const db = { collection() { return { doc() {} }; }, runTransaction(fn) { return fn({ get: async () => ({ exists: false }) }); } };
  await assert.rejects(promoteMunicipality(request(), auth, db), { code: 'failed-precondition' });
  await assert.rejects(promoteMunicipality(request(), { getUserByEmail: async () => ({ disabled: true }) }, db), { code: 'failed-precondition' });
});
