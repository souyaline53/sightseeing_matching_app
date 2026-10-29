// Node.js 20+。先に firebase emulators:start --only auth,firestore を実行する。
// 接続先はローカル固定。本番のアカウント・ドキュメントは作成しない。
import assert from 'node:assert/strict';

const project = 'sightseeing-matching-prototype';
const auth = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const firestore = `http://127.0.0.1:8080/v1/projects/${project}/databases/(default)/documents`;
const users = [];
const string = value => ({stringValue: value});
async function request(url, {token, ...options} = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {})},
  });
  const body = await response.json().catch(() => ({}));
  return {status: response.status, body};
}
async function account(email, password) {
  return request(`${auth}/accounts:signUp?key=emulator-only`, {
    method: 'POST', body: JSON.stringify({email, password, returnSecureToken: true}),
  });
}
async function write(user, uid, fields, create = true) {
  return request(`${firestore}:commit`, {
    token: user.idToken, method: 'POST',
    body: JSON.stringify({writes: [{
      update: {name: `projects/${project}/databases/(default)/documents/users/${uid}`, fields},
      updateTransforms: [
        ...(create ? [{fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME'}] : []),
        {fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME'},
      ],
    }]}),
  });
}
try {
  const suffix = `${Date.now()}-${process.pid}`;
  const weak = await account(`weak-${suffix}@example.test`, 'abcde');
  assert.notEqual(weak.status, 200, '5文字のパスワードを拒否');
  for (const name of ['alice', 'bob']) {
    const result = await account(`${name}-${suffix}@example.test`, 'abcdef');
    assert.equal(result.status, 200, `6文字の英小文字のみで登録: ${result.body.error?.message ?? ''}`);
    users.push(result.body);
  }
  const [alice, bob] = users;
  const fields = {
    uid: string(alice.localId), nickname: string('たびすけ'), ageGroup: string('30代'),
    prefecture: string('北海道'), municipality: string('札幌市'),
  };
  assert.equal((await write(alice, alice.localId, fields)).status, 200, '本人のプロフィール作成');
  const own = await request(`${firestore}/users/${alice.localId}`, {token: alice.idToken});
  assert.equal(own.status, 200);
  assert.equal(own.body.fields.nickname.stringValue, 'たびすけ');
  assert.equal((await request(`${firestore}/users/${alice.localId}`, {token: bob.idToken})).status, 403, '他人の住所などは取得不可');
  assert.equal((await request(`${firestore}/users/${alice.localId}`)).status, 403, '未認証では取得不可');
  assert.equal((await request(`${firestore}/users`, {token: alice.idToken})).status, 403, '一覧取得不可');
  assert.equal((await write(bob, alice.localId, fields)).status, 403, '他人のプロフィール更新不可');
  assert.equal((await write(alice, bob.localId, {...fields, uid: string(bob.localId)})).status, 403, '他人のIDで作成不可');
  const updated = {...own.body.fields, nickname: string('旅のつづき')};
  assert.equal((await write(alice, alice.localId, {...updated, password: string('abcdef')}, false)).status, 403, 'パスワードをFirestoreに保存不可');
  assert.equal((await write(alice, alice.localId, {...updated, ageGroup: string('不正値')}, false)).status, 403, '不正な属性を拒否');
  assert.equal((await write(alice, alice.localId, updated, false)).status, 200, '本人による属性編集');
  const edited = await request(`${firestore}/users/${alice.localId}`, {token: alice.idToken});
  assert.deepEqual(edited.body.fields.createdAt, own.body.fields.createdAt);
  const login = await request(`${auth}/accounts:signInWithPassword?key=emulator-only`, {
    method: 'POST', body: JSON.stringify({email: alice.email, password: 'abcdef', returnSecureToken: true}),
  });
  assert.equal(login.status, 200);
  assert.equal(login.body.localId, alice.localId, '再ログインしてもUIDを維持');
  console.log('PASS: Auth登録・再ログイン・6文字パスワード、Firestore本人限定アクセス・属性検証・編集');
} finally {
  for (const user of users) {
    await request(`${firestore}/users/${user.localId}`, {token: user.idToken, method: 'DELETE'});
    await request(`${auth}/accounts:delete?key=emulator-only`, {
      method: 'POST', body: JSON.stringify({idToken: user.idToken}),
    });
  }
}
