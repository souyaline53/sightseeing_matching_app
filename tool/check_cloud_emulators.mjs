// ローカルのAuth/Firestore/Storageだけを検証。本番には接続しない。
import assert from 'node:assert/strict';
const project = 'sightseeing-matching-prototype';
const bucket = `${project}.firebasestorage.app`;
const auth = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const db = `http://127.0.0.1:8080/v1/projects/${project}/databases/(default)/documents`;
const storage = `http://127.0.0.1:9199/v0/b/${bucket}/o`;
const created = [], files = [];
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
async function request(url, {token, headers = {}, ...opts} = {}) {
  const response = await fetch(url, {...opts, headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {}), ...headers}});
  const body = await response.json().catch(() => ({})); return {status: response.status, body};
}
async function signUp(email) {
  const result = await request(`${auth}/accounts:signUp?key=local-only`, {method: 'POST', body: JSON.stringify({email, password: 'abcdef', returnSecureToken: true})});
  assert.equal(result.status, 200, `ローカルテストユーザーの作成: ${result.body.error?.message ?? ''}`);
  created.push(result.body); return result.body;
}
async function commit(user, collection, id, fields, creating = true) {
  return request(`${db}:commit`, {token: user?.idToken, method: 'POST', body: JSON.stringify({writes: [{
    update: {name: `projects/${project}/databases/(default)/documents/${collection}/${id}`, fields},
    updateTransforms: [...(creating ? [{fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME'}] : []), {fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME'}],
  }]})});
}
const str = stringValue => ({stringValue}); const num = value => ({integerValue: String(value)});
const empty = {arrayValue: {values: []}};
const spot = {title: str('クラウドの体験'), area: str('北海道'), category: str('自然'), description: str('紹介'), story: str('物語'), surprise: str('発見'), minutes: num(60), accessMinutes: num(90), order: num(0), photo: str(''), photoPath: str(''), additionalPhotos: empty, additionalPhotoPaths: empty};
async function upload(user, path, bytes = png, type = 'image/png') {
  const result = await request(`${storage}?name=${encodeURIComponent(path)}&uploadType=media`, {
    token: user?.idToken, method: 'POST', headers: {'Content-Type': type, 'X-Goog-Upload-Protocol': 'raw'}, body: bytes,
  });
  if (result.status === 200) files.push({user, path}); return result;
}
let admin;
try {
  admin = await signUp('nichi-ka@nichi-ka.com');
  const other = await signUp(`cloud-${Date.now()}@example.test`);
  const guestResult = await request(`${auth}/accounts:signUp?key=local-only`, {method: 'POST', body: JSON.stringify({returnSecureToken: true})});
  assert.equal(guestResult.status, 200); const guest = guestResult.body; created.push(guest);
  assert.equal((await commit(null, 'sightseeing_spot', 'security-test', spot)).status, 403);
  assert.equal((await commit(other, 'sightseeing_spot', 'security-test', spot)).status, 403);
  assert.equal((await commit(admin, 'sightseeing_spot', 'security-test', spot)).status, 403, '未確認メールでは管理者権限なし');
  const verify = await request(`${auth}/accounts:update?key=local-only`, {token: 'owner', method: 'POST', body: JSON.stringify({localId: admin.localId, emailVerified: true})});
  assert.equal(verify.status, 200);
  const login = await request(`${auth}/accounts:signInWithPassword?key=local-only`, {method: 'POST', body: JSON.stringify({email: admin.email, password: 'abcdef', returnSecureToken: true})});
  admin = {...admin, ...login.body};
  assert.equal((await commit(admin, 'sightseeing_spot', 'security-test', spot)).status, 200, '確認済み管理者が追加可能');
  const read = await request(`${db}/sightseeing_spot/security-test`); assert.equal(read.status, 200, 'ゲストも閲覧可能');
  assert.equal((await commit(admin, 'sightseeing_spot', 'security-test', {...read.body.fields, minutes: num(-1)}, false)).status, 403);
  assert.equal((await commit(admin, 'sightseeing_spot', 'security-test', {...read.body.fields, title: str('変更済み')}, false)).status, 200);
  const transit = {position: str('any'), spotId: str('*'), mode: str('JR（サンプル）'), transfer: str('なし'), walking: str('5分'), fare: str('500円'), departureMinutes: num(600), arrivalMinutes: num(630), stepMinutes: num(60), note: str('サンプル時刻・実際の運行情報ではありません'), order: num(0), photo: str(''), photoPath: str('')};
  assert.equal((await commit(other, 'transit', 'security-test', transit)).status, 403);
  assert.equal((await commit(admin, 'transit', 'security-test', transit)).status, 403, '旧交通案内は廃止');
  // 新交通マスターは匿名閲覧、確認済み管理者のみ書き込み可能。
  for (const collection of ['transport_agencies','transport_stops','transport_routes','transport_services','transport_trips','transport_fares']) {
    const fields = {name:str('架空・権限検証専用'), verificationStatus:str('sample')};
    assert.equal((await commit(null,collection,'transport-security-test',fields)).status,403);
    assert.equal((await commit(guest,collection,'transport-security-test',fields)).status,403);
    assert.equal((await commit(other,collection,'transport-security-test',fields)).status,403);
    assert.equal((await commit(admin,collection,'transport-security-test',fields)).status,200);
    assert.equal((await request(`${db}/${collection}/transport-security-test`)).status,200);
    await request(`${db}/${collection}/transport-security-test`,{token:'owner',method:'DELETE'});
  }
  const accessSpot = {...read.body.fields, accessStops: {arrayValue:{values:[{mapValue:{fields:{stopId:str('sample_stop'),walkingMinutes:{nullValue:null},verificationStatus:str('unverified')}}}]}}, accessNotes:str('入口まで未確認')};
  assert.equal((await commit(admin,'sightseeing_spot','security-test',accessSpot,false)).status,200,'追加アクセス情報を管理者が保存可能');
  assert.equal((await commit(other,'sightseeing_spot','security-test',accessSpot,false)).status,403);
  // 投稿本文・評価とリアクションもFirestoreのルールで保護する。
  const postId = 'cloud-post-security-test';
  const postFields = {
    id: str(postId), userId: str(other.localId), userName: str('投稿者'), avatar: str(''),
    spotId: str('security-test'), category: str('自然'), caption: str('クラウド本文'),
    rating: {doubleValue: 4.5}, status: str('active'),
    media: {arrayValue: {values: [{mapValue: {fields: {
      id: str('image'), source: str('https://firebasestorage.googleapis.com/image'),
      mimeType: str('image/png'), storagePath: str(`posts/${other.localId}/${postId}/image.png`),
    }}}]}},
  };
  async function createDoc(user, collection, id, fields) {
    return request(`${db}:commit`, {token: user?.idToken, method: 'POST', body: JSON.stringify({writes: [{
      update: {name: `projects/${project}/databases/(default)/documents/${collection}/${id}`, fields},
      updateTransforms: [{fieldPath:'createdAt', setToServerValue:'REQUEST_TIME'}],
    }]})});
  }
  assert.equal((await createDoc(guest,'posts',postId,postFields)).status,403,'投稿者UIDの偽装を拒否');
  assert.equal((await createDoc(other,'posts',postId,{...postFields,caption:str('x'.repeat(2001))})).status,403,'本文の上限をサーバーでも検証');
  assert.equal((await createDoc(other,'posts',postId,postFields)).status,200,'入力した投稿本文を保存');
  assert.equal((await request(`${db}/posts/${postId}`)).body.fields.caption.stringValue,'クラウド本文');
  const patch = (user,fields,mask) => request(`${db}/posts/${postId}?updateMask.fieldPaths=${mask}`,{token:user.idToken,method:'PATCH',body:JSON.stringify({fields})});
  assert.equal((await patch(admin,{caption:str('改ざん')},'caption')).status,403,'他人の本文変更を拒否');
  assert.equal((await request(`${db}/posts/${postId}`,{token:admin.idToken,method:'DELETE'})).status,403,'他人の投稿削除を拒否');
  const comment = {id:str('cloud-comment-test'),postId:str(postId),userId:str(guest.localId),userName:str('ゲストさん'),text:str('コメント')};
  assert.equal((await createDoc(guest,'post_comments','cloud-comment-test',comment)).status,200);
  assert.equal((await createDoc(other,'post_comments','forged-comment',{...comment,id:str('forged-comment')})).status,403);
  assert.equal((await createDoc(guest,'post_likes',`${postId}_${guest.localId}`,{postId:str(postId),userId:str(guest.localId)})).status,200);
  assert.equal((await createDoc(guest,`users/${guest.localId}/post_bookmarks`,postId,{targetId:str(postId)})).status,200);
  assert.equal((await request(`${db}/users/${guest.localId}/post_bookmarks`,{token:other.idToken})).status,403,'他人の保存一覧を取得不可');
  assert.equal((await createDoc(guest,`users/${guest.localId}/post_follows`,other.localId,{targetId:str(other.localId)})).status,200);
  assert.equal((await createDoc(guest,`users/${guest.localId}/post_follows`,guest.localId,{targetId:str(guest.localId)})).status,403);
  assert.equal((await patch(other,{status:str('deleting')},'status')).status,200);
  assert.equal((await createDoc(guest,'post_comments','late-comment',{...comment,id:str('late-comment')})).status,403,'削除中の投稿への追加を拒否');
  assert.equal((await request(`${db}/post_comments/cloud-comment-test`,{token:other.idToken,method:'DELETE'})).status,200);
  assert.equal((await request(`${db}/post_likes/${postId}_${guest.localId}`,{token:other.idToken,method:'DELETE'})).status,200);
  assert.equal((await request(`${db}/posts/${postId}`,{token:other.idToken,method:'DELETE'})).status,200);
  await request(`${db}/users/${guest.localId}/post_bookmarks/${postId}`,{token:guest.idToken,method:'DELETE'});
  await request(`${db}/users/${guest.localId}/post_follows/${other.localId}`,{token:guest.idToken,method:'DELETE'});
  assert.equal((await upload(null, 'catalog/sightseeing_spot/security-test/anonymous.png')).status, 403);
  assert.equal((await upload(other, 'catalog/sightseeing_spot/security-test/other.png')).status, 403);
  assert.equal((await upload(admin, 'catalog/sightseeing_spot/security-test/admin.png')).status, 200);
  assert.equal((await upload(admin, 'catalog/sightseeing_spot/security-test/admin.png')).status, 403, '既存画像の上書き不可');
  assert.equal((await upload(guest, `posts/${guest.localId}/test/guest.png`)).status, 200, '登録しないゲストも写真を投稿可能');
  assert.equal((await upload(other, `posts/${guest.localId}/test/other.png`)).status, 403);
  assert.equal((await upload(other, `posts/${other.localId}/test/video.mp4`, png, 'video/mp4')).status, 403);
  assert.equal((await upload(other, `posts/${other.localId}/test/limit.png`, Buffer.alloc(5000000))).status, 403, 'ちょうど5MBも拒否');
  assert.equal((await upload(other, `posts/${other.localId}/test/under.png`, Buffer.concat([png, Buffer.alloc(200000 - png.length)]))).status, 200, '表示用画像200KBまでは許可');
  assert.equal((await upload(other, `posts/${other.localId}/test/over-display.png`, Buffer.concat([png, Buffer.alloc(200001 - png.length)]))).status, 403, '表示用画像200KB超を拒否');
  console.log('PASS: 新交通6コレクションの公開読取・管理者書込、観光地accessStops、カタログ管理者権限・表示画像200KB制限、投稿本文・評価・コメント・いいねの保存、UID偽装・他人の変更・個人情報取得の拒否');
} finally {
  // 専用エミュレーター内の、このスクリプトの文書だけを後片付けする。
  for (const path of ['posts/cloud-post-security-test','post_comments/cloud-comment-test','post_comments/forged-comment','post_comments/late-comment',
    ...created.flatMap(u => [`post_likes/cloud-post-security-test_${u.localId}`,`users/${u.localId}/post_bookmarks/cloud-post-security-test`,
      ...created.map(target => `users/${u.localId}/post_follows/${target.localId}`)])]) {
    await request(`${db}/${path}`, {token:'owner', method:'DELETE'});
  }
  if (admin) for (const collection of ['sightseeing_spot', 'transit']) await request(`${db}/${collection}/security-test`, {token: admin.idToken, method: 'DELETE'});
  for (const {user, path} of files) await request(`${storage}/${encodeURIComponent(path)}`, {token: user.idToken, method: 'DELETE'});
  for (const user of created) await request(`${auth}/accounts:delete?key=local-only`, {method: 'POST', body: JSON.stringify({idToken: user.idToken})});
}
