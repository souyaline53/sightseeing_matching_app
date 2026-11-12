# TABISAKI Dify連携基盤

## データフロー

質問3問（選択肢のラベル）＋検索条件（プロフィールから引き継いだ値を含む）＋保存済みID
→ `AiMatchingService` → Firebase匿名認証／既存ログイン → asia-northeast1 `getAiRecommendations`
→ UID単位のレート制限 → Firestore `sightseeing_spot` の候補取得
→ Dify Workflow（評価・条件分岐・順位・理由）
→ Functionsの構造・ID・重複・件数・理由型の検証
→ Flutterの既存カタログとIDで結合 → Dify順のカード（最大10件）

営業時間、季節、料金、興味、気分、交通手段、保存済みIDによる除外やスコア計算はFunctions／Flutterで行いません。ローカル推薦・模擬アクセス順位付けは検索と追加カードの実行経路から外しました。旧サービスは互換性用のファイル・単体テストとして残っています。

候補は最大30件。全件数を集計し、ドキュメントID順のランダムな開始位置から巡回して取得します。30件超の場合、毎回同じ先頭30件に固定されません。これは評価ではなく取得サンプリングです。小規模カタログでは全件を送信します。大量データではoffsetのスキップ読取りも課金されるため、サーバー管理のサンプリング索引などへの切替が必要です。近接IDの候補が同時に選ばれる方式で、独立一様抽出ではありません。全カタログからの最適な30件選定を保証するものではありません。

## 取得できるユーザー情報

| 元データ | 送信先 |
| --- | --- |
| 気分の回答ラベル | mood内のmood |
| 理由・探したい体験の回答ラベル | interests |
| 出発地（プロフィール既定値／今回の選択） | travelContext.origin |
| 移動手段 | transport: transit / car / either |
| 旅行期間 | tripLength: halfDay / day / overnight / longer |
| 旅行日 | visitDate: YYYY-MM-DD、日本時間で明日・週末を解決 |
| 同行者 | company: solo / friends / couple / family |
| 歩行量 | walking: light / normal / plenty |
| 予算 | budgetYen |
| 移動時間上限 | maxTravelMinutes（滞在可能時間とは異なる） |
| 保存済み観光地 | savedSpotIds（重複排除、最大100件） |

新規検索は旅程状態を初期化する前に保存済みIDを取得。既存旅程への追加は、その旅程の条件・旅行日・保存済みIDを使用し、元の検索画面の状態は保持します。質問未回答で追加する場合は「未設定」を送ります。

到着地・現在地・訪問予定地・訪問時刻・滞在可能時間は既存検索UIでは収集していないため送信しません。サーバーは任意の `destination / visitArea / visitDateTime / availableMinutes` を受け取れる構造ですが、新しい収集UIは追加していません。旅程の出発時刻は観光地到着時刻ではないため、visitDateTimeには流用しません。氏名・メール・年齢・アカウントプロフィール全体は送りません。

## Difyへの入力

**新しいDify入力変数は不要です。** `interests / mood / spots` の3変数を維持します。

- interests: 従来どおり文字列。
- mood: 旅行条件があれば `{mood, travelContext}` をJSON文字列化。旧クライアントから旅行条件がない場合は従来どおり普通の文字列。
- spots: 従来どおり候補配列のJSON文字列。各観光地に追加情報を含める。

実際の送信形式例（紙面のためspots内の観光地情報は一部だけ表示）：

```json
{
  "inputs": {
    "interests": "自然が生み出した、想像を超える景色、土地の物語に出会いたい",
    "mood": "{\"mood\":\"知らない世界にワクワクしたい\",\"travelContext\":{\"origin\":\"札幌駅\",\"transport\":\"transit\",\"tripLength\":\"day\",\"visitDate\":\"2026-11-13\",\"company\":\"solo\",\"walking\":\"normal\",\"budgetYen\":10000,\"maxTravelMinutes\":120,\"savedSpotIds\":[],\"timeZone\":\"Asia/Tokyo\"}}",
    "spots": "[{\"id\":\"TAKI\",\"name\":\"滝\",\"openingHoursStatus\":\"unknown\",\"openingHours\":null}]"
  },
  "response_mode": "blocking",
  "user": "Firebase UIDのSHA-256ダイジェスト"
}
```

spotsの1件をデコードした完全な形の例：

```json
{
  "id": "TAKI",
  "name": "滝",
  "title": "水と緑に出会う",
  "area": "北海道",
  "category": "自然",
  "description": "観光地の紹介",
  "story": "地域の物語",
  "surprise": "意外な魅力",
  "minutes": 60,
  "openingHoursStatus": "unknown",
  "openingHours": null,
  "specialHours": [],
  "seasonalAvailability": {"status": "unknown", "periods": []},
  "recommendedSeasons": [],
  "environmentType": "outdoor",
  "admissionFee": {"status": "unknown", "adultYen": null, "childYen": null, "note": ""},
  "reservationRequired": null,
  "experienceTags": ["自然", "絶景"],
  "officialUrl": "",
  "latitude": 43.0,
  "longitude": 141.0,
  "accessMinutes": 20,
  "accessNotes": "入口まで徒歩",
  "accessStops": [{"stopId": "stop", "stopName": "停留所", "walkingMinutes": 10, "walkingDistanceMeters": null, "isPrimary": true, "accessNotes": ""}]
}
```

旧データの営業時間・料金はunknown、未登録の数値はnull。曜日の欠落はnullとし、登録された空配列（休業）と区別します。写真URL・画像保存パス・管理用タイムスタンプは送りません。送信する文字列は原則2,000文字、補足500文字、配列100件までに制限し、spotsのJSONが500,000バイト超なら安全にエラーにします。これは容量制限であり推薦評価ではありません。

## Difyで手動設定すること

1. 開始ノードは `interests / mood / spots` を維持。mood・spotsは長文を受け取れる入力型・入力長制限に調整してください（既存の短いmood上限のままでは旅行条件を受信できません）。許容長は利用中Difyの設定と実データに合わせて確認してください。
2. Codeノードなどで `spots` をJSON配列として解析。moodはJSONとして解析でき、オブジェクトにmoodがあればその気分とtravelContextを取り出します。普通の文字列なら気分として扱い、追加条件は未設定とします。JSON化された文字列をそのまま既存プロンプトで読ませることもできますが、条件をノードで使うにはこの解析を追加してください。
3. 条件分岐／Code／LLMなどのノードで、興味・気分・営業・季節・料金・意外性・重み・保存済みIDの扱い・推薦順位を自由に設定。未取得の訪問時刻や滞在時間から開館可否を断定しないでください。unknownを営業中／無料とみなさないでください。祝日は自動営業扱いにしないでください。
4. 交通経路・時刻表・正確な移動時間・運賃はLLMに推測計算させないでください。accessMinutesは登録目安、accessStopsは既存交通検索の参照情報です。この変更で交通計算をDifyへ移してはいません。正確な計算が必要な次段階では既存交通検索APIから計算結果を取得する連携が必要です。
5. 候補のidだけを使い、最大10件の順序付き推薦と文字列reasonを生成。ユーザー入力・観光地紹介はデータとして扱い、そこに含まれる命令で出力契約や権限を変更させないでください。
6. 終了ノードの出力名を **recommendations**、値を下記オブジェクトにします。オブジェクトでもJSON文字列でも受信できます。出力変数追加・改名は不要です。

```json
{"recommendations":[{"spot_id":"TAKI","reason":"自然と美しい景観を楽しめる"}]}
```

Dify HTTPレスポンスの既存契約：

```json
{
  "data": {
    "status": "succeeded",
    "outputs": {
      "recommendations": {
        "recommendations": [{"spot_id":"TAKI","reason":"自然と美しい景観を楽しめる"}]
      }
    }
  }
}
```

FunctionsからFlutterへは `{"recommendations":[{"spot_id":"TAKI","reason":"自然と美しい景観を楽しめる"}]}`。
無効ID・重複・reasonが文字列でない項目は除外し、元の順の先頭10件を返します。理由は最大1,000文字。非空の出力が全件不正、構造不正、実行失敗は安全なエラー、正しい空配列は該当なし表示となります。

## 通信・セキュリティ

- Callableの検証済み `request.auth.uid` を必須とし、匿名・登録済み認証を許可。Flutterは未ログインなら匿名認証してから呼び出します。キーはSecret Manager `DIFY_API_KEY` のまま、クライアントへ配布しません。
- UIDごとにFirestore `_ai_request_limits/{sha256(uid)}` で1分6回。トランザクションで複数インスタンス間でも共有。入力検証後、Dify呼出前に回数を消費するため、通信失敗でも消費します。既存のcatch-allルールがクライアントの読書きを拒否します。Rulesの緩和は不要です。
- 匿名アカウントの作り直しを伴う濫用はUID制限だけでは防げません。全プラットフォームでApp Checkを設定・検証後、Functionsの環境変数 `AI_ENFORCE_APP_CHECK=true` で強制できます。初期値falseで既存接続を維持します。App Check SDKの導入・端末登録や設定変更は今回実施していません。
- DifyへはFirebase UIDそのものを渡さずSHA-256化した識別子を使用。無作為な匿名化ではなく継続的な仮名識別子です。旅行条件・回答は外部Difyへ送られるため、運用時にはサービスのプライバシー表示にも反映してください。
- Dify通信55秒、Functions90秒、Flutter90秒。HTTP・JSON不正・タイムアウト・ネットワーク障害を安全なエラーに変換。キー・本文・任意の上流エラー文字列のログ出力を削除しました。
- デプロイ、本番Firestore変更、実Dify APIへの課金呼出、Secretsの読取りは実施していません。Difyノードの変更・実ワークフローとの最終疎通は手動作業として残ります。

## 変更ファイル

- `functions/ai_matching.js`：取得、容量・入力制限、Dify通信、出力検証、レート制限。
- `functions/index.js`：既存Secret設定を維持、App Check強制の段階導入フラグ。
- `lib/service/ai_matching_service.dart`：既存サービスに型検証、認証、入力構築、注入可能な通信とProvider。実パスはservicesではなくserviceです。
- `lib/state/discovery_state.dart`：非同期推薦、Dify順・理由の保持、古い応答の破棄。
- `lib/service/search_execution_service.dart`：保存済みIDを初期化前に取得。
- `lib/screen/recommendation/experience_deck.dart`：既存カード・スワイプ・詳細・保存を維持し、理由／読込／再試行／該当なしを表示。
- `lib/screen/itinerary/add_experience_button.dart`：既存旅程への追加もDify経路へ変更。
- `functions/ai_matching.test.js`、`test/ai_matching_integration_test.dart`：新規テスト。
- `test/test_support.dart`、`test/widget_test.dart`：ネットワークを使わないDifyモックを共通テスト環境に追加。
- `test/settings_test.dart`、`test/conditions_steps_test.dart`：非同期呼出とDify順に期待を更新。
- 本ファイル。

## ローカル検証

- `node --test functions/ai_matching.test.js`：7件成功（旧データ、追加項目、ランダム候補、入力／出力、認証、レート、HTTP／JSON／タイムアウト）。
- `node --test functions/municipality.test.js functions/geocode.test.js functions/transport_router.test.js functions/transport_nearby_stops.test.js`：35件成功。
- `flutter test test/ai_matching_integration_test.dart test/widget_test.dart test/conditions_steps_test.dart test/settings_test.dart test/search_filter_sheet_test.dart test/cloud_catalog_test.dart test/add_experience_test.dart`：35件成功、1件失敗。追加4件はすべて成功（型・順序、Tokyo日付、読込・再試行・詳細・スワイプ保存、応答競合）。失敗は前回の作業でも再現した `add button also opens cards after restart with no question answers or saved trip`。空旅程状態でボタンが別のレイヤーに覆われ、タップが命中せず `showCoal` がNo elementになります。既存旅程からの追加2件は成功しています。既存の空旅程UIは今回の対象外として変更していません。

- `flutter analyze`：既存ファイルに14件（warning 5、info 9）。今回の変更箇所に新規指摘なし。
