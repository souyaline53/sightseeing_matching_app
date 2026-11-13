# Firebase Functions → TABISAKI_Transport_Optimizer

バックエンド実装・モックテストまで完了。本番デプロイ、Secret値の取得、実Difyリクエストは行っていない。Flutter/UI、既存マッチング、GTFS生成、既存Firestoreデータ・索引・Rulesは変更していない。

## FunctionとSecret

- Callable名: `optimizeTransportItinerary`
- 第2世代、Node.js 22/CommonJS、リージョン: `asia-northeast1`
- 既存codebase: `tabisaki`、source: `functions`
- `defineSecret('DIFY_TRANSPORT_API_KEY')`を`secrets`に明示バインド。ハンドラーからgetterを渡し、認証・入力検証後の実行時だけ`.value()`を呼ぶ。Secret値はソース・ログ・レスポンスに出さない。既存`DIFY_API_KEY`と独立。
- Functions 120秒、Dify fetch/応答読取90秒、maxInstances=2、concurrency=1、memory=512MiB。
- Firebase Authenticationの検証済み`request.auth.uid`が必須。匿名認証を含むFirebase認証を許可（既存マッチングと同じ扱い）。未認証はunauthenticated。
- App Checkは既存と同じ `AI_ENFORCE_APP_CHECK === 'true'` に従う。SDK導入や環境設定は今回変更していない。

## Callable入力とサイズ

```json
{"transport_data":"{\"schemaVersion\":1, ...交通ネットワーク全体...}"}
```

`transport_data`はJSON**文字列**だけを受け取る。クライアント指定のuser・endpoint・キー等は受け付けない。schemaVersion、旅行日・時間窓、交通手段、policy、地点roles、1〜3観光地の滞在・営業、アクセス、stops/routes/agencies/instances/segments/transfersの形式・参照・時刻・乗降型等を検証する。運行日抽出・経路探索は重複実装しない。クライアントのGTFSがFirestore原本と同一かを照合する責務も持たない。

既存serializeを再利用し、値・IDを保ったコンパクトJSONで転送する。raw入力は4,000,000 bytes以内、compact後は4,000,000文字（UTF-16にも適用）かつ4,000,000 bytes以内（2026-11-13時点の上限）。超過はresource-exhausted、途中切捨てなし。改行を含むrawも上限検査対象なので、生成済みコンパクト文字列を渡す。

既存2観光地軽量サンプルによるローカル実測:

- network: 350,585文字、352,129 UTF-8 bytes。
- `{"data":{"transport_data":...}}`というCallableのJSONエンベロープも含めてサイズをモックテストで検証。384,301 bytes（1MiB未満）。
- 第2世代の非圧縮HTTPリクエスト上限は32MBで、今回のアプリ上限の方が小さい。[Firebase公式上限](https://firebase.google.com/docs/functions/quotas)。実インターネット経由のCallable往復は未実施。

2026-11-13に明示許可のもとGET /info・GET /parametersを読み取り、公開アプリTABISAKI_Transport_Optimizer（workflow）の必須入力transport_dataがjson_object型であることを確認した。Functionsは検証済みJSONをオブジェクトとしてDifyへ送る。FlutterからCallableへのJSON文字列契約は維持する。Difyを文字列入力へ戻した環境のみDIFY_TRANSPORT_INPUT_TYPE=stringを明示できる。失敗時に型を変えて自動再送はしない。

以前の`prepareTransportOptimization`は`inputs.transport_json`を返す。今回その既存契約は変更していない。新Callableへ渡す際に、その文字列を`transport_data`へマッピングする。二重JSONエンコードしない。

## Difyリクエスト

固定endpoint `POST https://api.dify.ai/v1/workflows/run`。

```json
{
  "inputs": {"transport_data": {"schemaVersion": 1, "...": "交通ネットワーク全体"}},
  "response_mode": "blocking",
  "user": "Firebase UIDのSHA-256（64桁）"
}
```

Authorizationは実行時SecretからのBearer、Content-Typeはapplication/json。UIDそのものは送らず、継続的な仮名識別子を使う。任意endpointやHTTP redirectは許可しない。HTTPリクエストは1回のみで自動リトライなし。[Dify公式API概要](https://docs.dify.ai/en/api-reference/guides/get-started)。

## Dify応答 → Callable応答

`data.status === 'succeeded'`を確認し、`data.outputs`から以下を取得する。

```json
{
  "recommendation": true,
  "itinerary_json": "{\"status\":\"feasible\",\"candidateId\":\"candidate_001\",...}",
  "message": "旅程生成成功: 3222文字"
}
```

- recommendationまたはsuccessのbooleanが必須。両方ある場合は同値が必要。
- itinerary_jsonは文字列として受け取りJSON解析。statusを持つオブジェクトであることを確認する。
- Code ④の旅程オブジェクトは省略・再編成せず全体を返す。feasible以外のstatusも保持する。未知のCode ④内部フィールドをホワイトリストで削除しない。
- 成功フラグfalseの場合も、正しい旅程JSONがあればsuccess=falseで返す。booleanの文字列化（"true"等）は受け付けない。
- Difyのmessageや内部エラーは転送せず、messageを固定の「旅程生成成功」または「旅程を生成できませんでした」にする。応答にSecret文字列が含まれる場合も拒否する。

```json
{
  "success": true,
  "itinerary": {"status": "feasible", "candidateId": "candidate_001", "...": "Code ④の残りの全フィールド"},
  "message": "旅程生成成功"
}
```

## エラーと利用制限

- 未認証: unauthenticated。不正JSON・形式・参照: invalid-argument。
- 容量超過、UID頻度超過、Dify HTTP429: resource-exhausted。
- Secret未設定・Dify401/403: failed-precondition。
- タイムアウト: deadline-exceeded。通信失敗・その他HTTPエラー: unavailable。
- Workflow失敗、不正/過大応答・出力矛盾: internal。
- Dify応答本文はストリームで最大1,000,000 bytes。HTTPエラー本文は読取り・ログ・転送しない。例外の任意メッセージや巨大なGTFSはログへ出さない。

UIDごとに1分3回をFirestoreトランザクションで制限する。新規の内部コレクション`_transport_optimizer_request_limits/{sha256(uid)}`にstartedAt/countのみ保存。既存catch-all Rulesでクライアントアクセスは拒否され、Rules変更は不要。GTFSコレクションは変更しない。入力とSecret検証後、Dify呼出前に回数を消費するため、失敗時も消費する。トランザクション内部リトライはあり得るが、その中でDifyは呼ばない。

maxInstances=2/concurrency=1とUID制限を実装済み。公開前には既存App Checkの有効化状況を確認する。匿名UIDを作り直す濫用や複数UIDの合計利用量はUID制限だけでは抑えられないため、利用実績に応じた全体上限・監視を次段階で検討する。追加の有料外部サービスは導入していない。HTTPがタイムアウトしてもDify側で処理が続く可能性があるため、Flutter側も自動再試行をしない。

## 変更ファイル・テスト

- `functions/transport_dify.js`: 入力検証、既存serialize再利用、UID制限、Dify通信・出力解析。
- `functions/index.js`: 独立Secret定義とCallable exportのみ追加。
- `functions/transport_dify.test.js`: 通信モック、両出力名、全旅程保持、認証、形式・容量、頻度制限、エラー/timeout、Secret非漏洩、既存export/Secret維持。
- 本書。

新規11テスト成功。既存AIマッチング・交通生成・軽量化・交通検索と合わせて52件成功。実Secret・実Dify課金呼出しは0回、公開Workflowとの最終疎通は未実施。

## デプロイ（今回未実行）

既存Secretは登録済みという前提なので再登録・値の表示は不要。

```sh
firebase deploy --only functions:tabisaki:optimizeTransportItinerary --project sightseeing-matching-prototype
```

既存のFirebase CLI認証・Blaze/Functions設定・実行サービスアカウントのSecret参照権限を使う。CLIがSecret権限不足を報告した場合は、そのSecretへの必要なアクセス権を確認する。[Firebase Secret parameters](https://firebase.google.com/docs/functions/config-env#secret_parameters)。

## 将来のFlutter呼出し情報（UI変更なし）

認証後、リージョンをasia-northeast1、Callable名をoptimizeTransportItinerary、タイムアウトを130秒などFunctionsより長く指定する。

```dart
final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast1')
    .httpsCallable('optimizeTransportItinerary',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 130)));
final response = await callable.call({'transport_data': prepared.transportJson});
// response.data: success / itinerary（Code ④の全オブジェクト） / message
```

すでにJSON文字列であるprepared.transportJsonへjsonEncodeを重ねない。APIキー・Authorization・userはFlutterから送らない。既存Functions呼出し・交通生成のProvider・画面には接続していない。
