// 公開画像を1件だけ読み取り、Webの画像キャッシュに必要なCORS応答を確認する。
// 認証情報を使わず、Firestore・Storageへの書き込みも行わない。
const project = 'sightseeing-matching-prototype';
const origin = new URL(process.argv[2] ?? 'http://localhost:7357').origin;

async function check() {
  const catalogUrl = new URL(
    `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/sightseeing_spot`,
  );
  catalogUrl.searchParams.set('pageSize', '100');
  catalogUrl.searchParams.set('mask.fieldPaths', 'photo');
  const catalogResponse = await fetch(catalogUrl, {
    signal: AbortSignal.timeout(20000),
  });
  if (!catalogResponse.ok) {
    throw new Error(`カタログを取得できません（HTTP ${catalogResponse.status}）。`);
  }
  const catalog = await catalogResponse.json();
  const photo = catalog.documents
    ?.map((doc) => doc.fields?.photo?.stringValue)
    .find((url) => url?.startsWith('https://'));
  if (!photo) throw new Error('検証対象の画像がありません。');
  const response = await fetch(photo, {
    headers: { Origin: origin },
    signal: AbortSignal.timeout(20000),
  });
  await response.body?.cancel();
  if (!response.ok) {
    throw new Error(`画像を取得できません（HTTP ${response.status}）。`);
  }
  if (!response.headers.get('content-type')?.startsWith('image/')) {
    throw new Error('画像以外の応答が返されました。');
  }
  const allowed = response.headers.get('access-control-allow-origin');
  if (allowed !== '*' && allowed !== origin) {
    throw new Error(
      `画像は存在しますが、${origin} からの取得を許可するCORSヘッダーがありません。storage.cors.jsonをバケットに反映してください。`,
    );
  }
  console.log(`PASS: ${origin} からの画像取得に必要なCORSヘッダーを確認しました。`);
}

check().catch((error) => {
  // 写真のトークン付きURLをエラーログに含めない。
  console.error(`FAIL: ${error.message}`);
  process.exitCode = 1;
});
