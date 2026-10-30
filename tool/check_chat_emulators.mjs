// 検証先はローカル限定。本番のユーザーや会話は変更しない。
import assert from 'node:assert/strict';
const project = 'sightseeing-matching-prototype';
const base = `http://127.0.0.1:8080/v1/projects/${project}/databases/(default)/documents`;
const prefix = `projects/${project}/databases/(default)/documents/`;
const auth = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const callable = `http://127.0.0.1:5001/${project}/asia-northeast1/setMunicipalityUser`;
const users = [], documents = new Set();
const str = (value) => ({ stringValue: value });
const strings = (values) => ({ arrayValue: { values: values.map(str) } });

async function request(url, user, method = 'GET', body) {
  const response = await fetch(url, {
    method, headers: { 'Content-Type': 'application/json', ...(user ? { Authorization: `Bearer ${user.idToken ?? user}` } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(30000),
  });
  return { status: response.status, body: await response.json().catch(() => ({})) };
}
async function signup(email) {
  const r = await request(`${auth}/accounts:signUp?key=local`, null, 'POST', { ...(email ? { email, password: 'abcdef' } : {}), returnSecureToken: true });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  users.push(r.body); return r.body;
}
async function write(user, path, fields, transforms = [], mask) {
  documents.add(path);
  return request(`${base}:commit`, user, 'POST', { writes: [{
    update: { name: prefix + path, fields },
    ...(mask ? { updateMask: { fieldPaths: mask } } : {}),
    updateTransforms: transforms.map((fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })),
  }] });
}
async function profile(user, name, legacy = false) {
  const path = `users/${user.localId}`;
  const fields = { uid: str(user.localId), nickname: str(name), ageGroup: str('30代'), prefecture: str('北海道'), municipality: str('札幌市'), ...(legacy ? {} : { userType: str('general') }) };
  assert.equal((await write(user, path, fields, ['createdAt', 'updatedAt'])).status, 200);
  const visible = { uid: str(user.localId), displayName: str(name), userType: str('general') };
  assert.equal((await write(user, `public_profiles/${user.localId}`, visible, ['updatedAt'])).status, 200);
  return { fields, visible };
}
async function send(user, roomId, messageId, text, senderId = user.localId) {
  const path = `chat_rooms/${roomId}/messages/${messageId}`;
  documents.add(path);
  return request(`${base}:commit`, user, 'POST', { writes: [
    { update: { name: prefix + path, fields: { senderId: str(senderId), text: str(text) } },
      updateTransforms: [{ fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME' }] },
    { update: { name: prefix + `chat_rooms/${roomId}`, fields: { lastMessage: str(text), lastSenderId: str(senderId), lastMessageId: str(messageId) } },
      updateMask: { fieldPaths: ['lastMessage', 'lastSenderId', 'lastMessageId', 'updatedAt'] },
      updateTransforms: [{ fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' }] },
  ] });
}

try {
  const stamp = Date.now();
  let admin = await signup('nichi-ka@nichi-ka.com');
  const traveler = await signup(`traveler-${stamp}@example.test`);
  const town = await signup(`town-${stamp}@example.test`);
  const outsider = await signup(`outsider-${stamp}@example.test`);
  const guest = await signup();
  const original = await profile(traveler, '旅の仲間', true);
  const townProfile = await profile(town, '観光案内');
  await profile(outsider, '会話外の利用者');
  const promote = (user, email = town.email) => request(callable, user, 'POST', { data: { email } });
  assert.equal((await promote(null)).status, 401);
  assert.equal((await promote(traveler)).status, 403);
  assert.equal((await promote(admin)).status, 403, '未確認管理者も変更不可');
  assert.equal((await write(town, `users/${town.localId}`, { userType: str('municipality') }, ['updatedAt'], ['userType', 'updatedAt'])).status, 403, '自己昇格を拒否');
  assert.equal((await write(town, `public_profiles/${town.localId}`, { ...townProfile.visible, userType: str('municipality') }, ['updatedAt'])).status, 403, '公開バッジ偽装を拒否');
  assert.equal((await request(`${base}/users/${town.localId}`, traveler)).status, 403, '相手の私的プロフィールは非公開');
  assert.equal((await request(`${base}/public_profiles/${town.localId}`, guest)).status, 403, '匿名利用者へのディレクトリ公開を拒否');
  const verified = await request(`${auth}/accounts:update?key=local`, 'owner', 'POST', { localId: admin.localId, emailVerified: true });
  assert.equal(verified.status, 200);
  admin = (await request(`${auth}/accounts:signInWithPassword?key=local`, null, 'POST', { email: admin.email, password: 'abcdef', returnSecureToken: true })).body;
  const missing = await promote(admin, `missing-${stamp}@example.test`);
  assert.equal(missing.status, 404);
  assert.equal(missing.body.error.details.reason, 'user-not-found');
  const promoted = await promote(admin);
  assert.equal(promoted.status, 200, JSON.stringify(promoted.body));
  assert.equal(promoted.body.result.userType, 'municipality');
  const visible = (await request(`${base}/public_profiles/${town.localId}`, traveler)).body.fields;
  assert.deepEqual(Object.keys(visible).sort(), ['displayName', 'uid', 'updatedAt', 'userType']);
  assert.equal(visible.userType.stringValue, 'municipality');
  const privateProfile = (await request(`${base}/users/${town.localId}`, town)).body.fields;
  assert.equal(privateProfile.ageGroup.stringValue, '30代');
  assert.equal((await write(town, `users/${town.localId}`, { ...privateProfile, nickname: str('更新後の観光案内') }, ['updatedAt'])).status, 200, '通常のプロフィール編集で自治体属性を維持');
  assert.equal((await write(town, `users/${town.localId}`, { userType: str('general') }, ['updatedAt'], ['userType', 'updatedAt'])).status, 403, '本人による属性変更を拒否');
  assert.equal((await write(traveler, `users/${traveler.localId}`, { userType: str('general') }, ['updatedAt'], ['userType', 'updatedAt'])).status, 200, '旧アカウントは一般属性で移行可能');
  assert.equal((await request(`${base}/users/${traveler.localId}`, traveler)).body.fields.nickname.stringValue, original.fields.nickname.stringValue);
  const roomId = `chat-security-${stamp}`;
  const room = { members: strings([traveler.localId, town.localId]), lastMessage: str(''), lastSenderId: str(''), lastMessageId: str('') };
  assert.equal((await request(`${base}/chat_rooms/${roomId}`, traveler)).status, 404, '作成前のルーム確認が可能');
  assert.equal((await write(guest, `chat_rooms/${roomId}`, room, ['createdAt', 'updatedAt'])).status, 403);
  assert.equal((await write(outsider, `chat_rooms/${roomId}`, room, ['createdAt', 'updatedAt'])).status, 403);
  assert.equal((await write(traveler, `chat_rooms/${roomId}`, room, ['createdAt', 'updatedAt'])).status, 200);
  assert.equal((await request(`${base}/chat_rooms/${roomId}`, town)).status, 200);
  assert.equal((await request(`${base}/chat_rooms/${roomId}`, outsider)).status, 403);
  assert.equal((await request(`${base}/chat_rooms/${roomId}/messages`, outsider)).status, 403);
  assert.equal((await request(`${base}/chat_rooms`, traveler)).status, 403, '会話の無制限な一覧取得を拒否');
  const query = { structuredQuery: { from: [{ collectionId: 'chat_rooms' }], where: { fieldFilter: { field: { fieldPath: 'members' }, op: 'ARRAY_CONTAINS', value: str(traveler.localId) } } } };
  assert.equal((await request(`${base}:runQuery`, traveler, 'POST', query)).status, 200, '自分の会話だけ一覧取得');
  assert.equal((await send(traveler, roomId, 'forged', '偽装', town.localId)).status, 403);
  assert.equal((await send(outsider, roomId, 'outside', '侵入')).status, 403);
  assert.equal((await send(traveler, roomId, 'long', 'x'.repeat(2001))).status, 403);
  assert.equal((await write(traveler, `chat_rooms/${roomId}/messages/orphan`, { senderId: str(traveler.localId), text: str('プレビューを更新しない') }, ['createdAt'])).status, 403);
  assert.equal((await send(traveler, roomId, 'hello', '行き方を教えてください')).status, 200);
  assert.equal((await send(town, roomId, 'reply', '公共交通で行けます')).status, 200);
  const preview = (await request(`${base}/chat_rooms/${roomId}`, traveler)).body.fields;
  assert.equal(preview.lastMessage.stringValue, '公共交通で行けます');
  assert.equal(preview.lastSenderId.stringValue, town.localId);
  const received = await request(`${base}/chat_rooms/${roomId}/messages/reply`, traveler);
  assert.equal(received.body.fields.text.stringValue, '公共交通で行けます');
  assert.equal((await write(traveler, `chat_rooms/${roomId}`, { members: strings([traveler.localId, outsider.localId]) }, [], ['members'])).status, 403, '途中で参加者を差し替え不可');
  assert.equal((await write(town, `chat_rooms/${roomId}/messages/hello`, { text: str('変更') }, [], ['text'])).status, 403, '送信済みメッセージの改変を拒否');
  console.log('PASS: 管理者のメール指定による属性変更・旧プロフィール互換・非公開情報保護・参加者限定チャット・双方向送信と最新プレビューを確認');
} finally {
  for (const path of [...documents].sort((a, b) => b.split('/').length - a.split('/').length)) {
    await request(`${base}/${path}`, 'owner', 'DELETE');
  }
  for (const user of users) {
    await request(`${auth}/accounts:delete?key=local`, 'owner', 'POST', { localId: user.localId });
  }
}
