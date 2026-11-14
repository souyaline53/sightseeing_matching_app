# AI旅程作成と利用制限

## 実装と画面

観光地一覧・推薦・スワイプから共通の旅程入力画面へ進み、保存した観光地を選択して手動またはAIの作成ボタンを押す。AIボタンは既存の編集画面へ移動して条件シートを開き、確定後にDifyを実行する。
旅程作成画面の出発時刻OutlinedButtonの隣に「AIで旅程を組み立てる」を配置。狭い画面では折り返す。説明パネル・採用確認は表示しない。処理中・結果不明・レート制限中はボタンを無効にする。成功した旅程も再度作成でき、旅程ごとの回数制限はない。

入力は角丸のmodal bottom sheetで、出発地と乗車駅・バス停、到着地と降車駅・バス停、出発日時、到着日時、各施設の滞在時間のみ。札幌の登録接続ではJR北海道「札幌」を初期選択する。乗り場自体を移動の端点とするため、その駅との徒歩接続は0秒で送る。観光地との徒歩時間は登録値を使用し、未確認値を使う場合は結果にも要確認を残す。徒歩時間の数値がない観光地は推測せず、入力画面で未登録地点を案内する。

到着日は既存の泊数条件（日帰り/1泊/2泊以上）から初期値を計算し、現在は旅行日から3日間（2泊）以内で選択可能。出発地と異なる到着地も保存・表示する。営業時間は観光地の曜日別・特別営業日・季節情報から取得。未登録の日時は営業している前提の時間窓とassumedOpenを送信し、結果へ「営業時間未確認（営業している前提）」を追加する。登録済みの定休日・休業期間は守る。確認チェック、営業時間や徒歩時間のユーザー入力は置かない。

生成が成功し、待機中に旅の条件が変更されていなければ、訪問順序・旅行日・出発地/到着地・出発時刻・滞在時間を反映し、自動的にしおり画面へ進む。追加の採用確認はない。失敗時は元の順序・日時・手動交通選択を保持する。成功前の編集があれば元提案だけ保存し、編集内容を上書きしない。

交通選択欄の最上部としおりの各区間に、既存カードに合わせたAI交通カードを表示する。「AIで作成」の小さなラベルを付け、実際の時刻・路線・停留所・徒歩情報を表示する。要確認ラベルをタップすると警告内容を確認できる。元のlegs/stepsは欠落させず保存し、地点ID付きのlegs、またはvisitsと時刻で区間分けできるstepsを表示する。境界や名称が不明な場合は便や時刻を捏造しない。

手動選択は従来UIのまま利用でき、その区間に保存する。別の便へ変えると前後の接続が成立する保証がないため、元のAI交通提案全体を再確認扱いにする。元提案はカードとして残すが、しおりの有効な交通としては使わない。並び替え、観光地追加・削除、滞在、出発地/到着地、旅行日、時刻、泊数、交通モードが変わると元提案を再確認扱いにし、しおりでは有効な交通として使用しない。自動の再生成は行わず、利用者がAIボタンから実行できる。元提案と現在の手動編集内容は分離する。

## 保存構造

既存の手動旅程は SharedPreferences のローカル保存のまま。AIを使う旅だけ次のサーバードキュメントも利用する。

`users/{uid}/ai_trips/{serverGeneratedId}`

| フィールド | 内容 |
| --- | --- |
| ownerUid | 認証所有者。サーバーのみ設定 |
| currentTrip | ユーザーが現在編集している TripState のコンパクトJSON文字列 |
| aiGenerationStatus | unused / processing / completed / failed / uncertain |
| aiGenerationRequestId | クライアントの操作ID |
| aiLeaseId | サーバー発行の排他的な予約ID |
| aiGenerationPhase | reserved / dispatched / finished / expired_before_dispatch |
| aiGenerationStartedAt / aiGeneratedAt | サーバーのミリ秒UTC時刻 |
| aiDifyCallCount | 送信直前のTransactionで加算するDify実行試行数 |
| aiWorkflowRunId | 応答に存在する場合のDify実行ID |
| aiResult | 圧縮済み旅程と参照ラベル、生成前提を含むJSON文字列 |
| aiVisitOrder / aiDisplayLookup / aiInput | 復旧用の元順序、参照ラベル、前提JSON |
| aiLastErrorCode | 秘密情報を含まないエラー分類 |

TripState.ai には rootId、status、requestId、config、generationBasis、result、resultRequestId、basis、enabled を保存する。複製時は rootId と lineage を継承する。ai のない過去の旅程も読み込める。
JSON文字列保存は Firestore で未対応の配列の入れ子（営業時間 windows 等）を避けるため。巨大なGTFSネットワークは保存しない。currentTrip / aiResult は180KB以内を基本とし、送信ネットワークの既存サイズ検査も維持する。

編集はローカル保存後、既存の保存キューからサーバーの currentTrip へ直列反映する。オフライン等の失敗は既存の保存失敗状態で知らせ、再保存できる。再起動時はローカル保存を復元し、編集画面ではサーバー状態も購読する。別端末では旅程作成画面のメニュー「保存したAIの旅を開く」から復元する。
同じrootの複製は利用枠を共有し、サーバーの currentTrip は最後に保存されたコピーを表す。複製それぞれの独立した履歴をクラウドで保存する設計ではない。

## サーバー制御

`registerAiTrip` と `optimizeTransportItinerary` は asia-northeast1 のGen2 Callable。既存の App Check 方針に従う。認証済みUIDの下にサーバーが旅程IDを発行する。`_ai_trip_aliases/{hash(uid,lineage)}` が同じ旅・その複製の管理IDを再利用する。任意の存在しない旅程IDや他ユーザーのIDでは実行できない。

呼び出しは次の形式。

```js
// 初回登録。生成はしない。
registerAiTrip({trip: tripStateJson, rootId: existingRootId /* 既存の場合だけ */})
// 既存GTFS生成コードをFunctions内で再利用。
optimizeTransportItinerary({tripId, requestId, input: transportOptimizationInput})
// 管理・既存の生成済み入力用途では同じtripId/requestIdとtransport_data文字列も受け付ける。
```

Flutter→Functionsの交通ネットワークはschemaVersion:1のJSON文字列を維持し、Functions→Difyの inputs.transport_data は公開開始ノードに合わせたJSONオブジェクトとして送る（2026-11-13の公開設定確認に基づく修正）。Dify Workflow、観光地マッチング、GTFSコレクションは変更しない。DIFY_TRANSPORT_API_KEY を Secret Manager から実行時に取得する。

Firestore Transactionで予約し、送信直前にも予約IDとphaseを検証する。同一要求の再送を含む同時要求で送信権を持てるのは1件。成功済みの同じrequestIdではキー取得・GTFS取得・Dify呼び出しなしで保存済み結果を返す。新しいrequestIdは再生成できる。結果は`ai_trips/{id}/generations/{requestId}`にもサーバーで保存し、後続の生成後でも古い要求の再送は再実行しない。サーバー返却値は従来の success / itinerary / message に aiMetadata（元順序・参照ラベル・前提）を追加する。

成功フラグがfalse、またはinfeasibleは使用済みにせずfailed。送信前の失敗も再試行可能。送信後のタイムアウトや応答不明、成功応答を解釈・保存できない場合は uncertain としてロックする。Difyから明示されたfailed/stoppedは再試行可能。

送信されていないreservedだけ10分後に復旧できる。「保存済み結果を確認」はサーバーを再読込し、この状態だけ登録処理のTransactionでfailedに戻す。古い実行が後から動いても異なるleaseまたは変更済みphaseでは送信できない。dispatched / uncertain は時間経過で解除しない。

結果不明時は運用者が aiWorkflowRunId とDify実行履歴を確認する。成功済みなら実際の結果を照合して aiResult 等を復元しcompletedにする。**結果不明のままunused/failedへ戻さない。** 自動のDify再呼び出しや照会は行わない。

ユーザー単位で予約10件/UTC日、既存の送信制限3件/分。失敗も予約回数に含める。maxInstances:2、concurrency:1、Functions120秒、Dify通信90秒、Flutter130秒。新規の別の旅には別枠を持たせ、日次上限は共通。新規IDの無制限作成や別アカウントによる濫用を完全に識別する仕組みではないため、本番は既存設定に沿ったApp Checkも運用する。

## Firestoreルール・インデックス

所有者は自分のAI旅程を読め、currentTrip文字列だけ更新できる。status / result / owner / 予約等はクライアントから更新不可。ドキュメント作成・削除もクライアントには許可しない。内部alias・日次制限は既存のdenyルールで保護する。
検索しない大きなcurrentTrip / aiResult / aiInput / aiDisplayLookupはインデックス対象から除外する。データ削除や既存データの移行は不要。

## 検証とデプロイ

実Firebase/Difyへの有料通信・本番デプロイは実行していない。FunctionsのTransactionはメモリモック、Flutterは差し替えた通信・保存実装で検証。Firestoreルールの実エミュレーター評価と別実機での往復通信は未実施。

- 最終検証：Functions全体91件成功。AI専用8件では同時実行、再送、所有者検証、失敗、結果不明、期限切れ予約と古い実行の競合を確認。
- 最終検証：Flutter関連32件成功（AI専用9件を含む）。条件入力前の未実行、成功/失敗、カードUI、復元、複製、編集中の遅延応答、手動操作を確認。変更したFlutter実装とAIテストの静的解析も問題なし。
- 既存テストの旧表示文を現行の文へ合わせ、狭い画面で交通シートを展開して手動選択を検証するよう調整した。製品の既存説明文は変更していない。

```sh
cd functions
npm test
cd ..
flutter test test/ai_trip_test.dart test/trips_test.dart test/transport_itinerary_service_test.dart test/itinerary_origin_test.dart test/itinerary_transport_schedule_test.dart test/itinerary_walk_test.dart

# 内容を確認後に実施。今回未実施。
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only "functions:tabisaki:registerAiTrip,functions:tabisaki:optimizeTransportItinerary"
```

既存prepareTransportOptimizationはFunctions内部で再利用するため、今回その関数のデプロイは不要。今回のoptimizeTransportItineraryはtripId/requestIdが必須で、旧transport_data単独の呼び出しは拒否する。Flutter更新とFunctions更新を同時期に公開する。

## 変更ファイル

- Flutter：lib/model/{trip_plan,optimized_transport_itinerary}.dart、lib/state/{trip_state,trip_library_state}.dart
- 通信：lib/service/transport/{ai_trip_repository,transport_itinerary_service}.dart
- UI：lib/screen/itinerary/itinerary_editor.dart と lib/screen/itinerary/widgets/{ai_trip_panel,itinerary_transport_sheet}.dart、lib/screen/shared/discovery/interest_search_flow.dart
- Functions：functions/{trip_ai,transport_dify,index}.js
- Rules/Index：firestore.rules、firestore.indexes.json
- Tests：functions/trip_ai.test.js、test/ai_trip_test.dart、test/{itinerary_origin,itinerary_walk,itinerary_transport_schedule}_test.dart


## 2026-11-12：交通入力容量の引き上げ

アプリ独自の入力上限を399,999文字・500,000 bytesから、**2,000,000文字・4,000,000 bytes（4 MB）**へ引き上げた。生成、Functionsでの受信検証、送信直前のシリアライズは `functions/transport_limits.js` の設定を共有する。Flutterの生成済みJSON送信チェックも同じ既定値に変更した。便・停留所・区間の削除や途中切り捨ては行わない。

`DIFY_TRANSPORT_MAX_CHARACTERS` / `DIFY_TRANSPORT_MAX_BYTES` を環境変数で明示している環境では、その値が優先される。古い小さい値を指定している場合は削除または更新してからデプロイする。Flutter側の既定値はアプリのビルドに含まれる。

- 容量超過：reason=transport-payload-too-large、実測文字数・bytes・上限、Dify未送信を返す。
- 抽出区間数・中間データの上限：reason=transport-segment-limit / transport-build-limit。時間帯の調整を案内する。
- 1分の制限：reason=ai-minute-limit、待機秒数を返す。
- 日次制限：reason=ai-daily-limit、上限回数と解除時刻を返す。
- Dify側HTTP429：reason=dify-rate-limit。送信後なので結果確認を案内し、無条件には再実行しない。

Flutterはこれらを別々に表示し、容量超過時は現在のサイズと次の操作を案内する。エラーは提案欄の表示に加えてSnackBarでも通知する。送信前の容量超過ではサーバー予約・日次回数・Dify呼び出しが発生しないことをモックで検証した。成功済み1旅程1回、日次10件・1分3件の制限は変更していない。以前の曖昧な表示だけでは実機でどの制限に当たったかは判別できない。

Difyの[入力Paragraph](https://docs.dify.ai/en/cloud/use-dify/nodes/user-input)と[Codeノードの出力制限](https://docs.dify.ai/en/cloud/use-dify/nodes/code)は別物。入力をCode②へ直接渡し、大きなtransport_data全体をCodeノードの出力として再返却しない構成を維持する。Dify CloudのCode出力400,000文字上限は今回変更していない。公開Workflowの開始変数にmax_lengthを設定している版では、その値も確認する。Dify Cloudが実際に4 MBの入力を処理できるかの実通信検証は行っていない。

最終テスト：Functions全95件、Flutter関連35件が成功。旧上限を超える有効JSONをそのまま送信すること、新上限超過では未送信になること、容量・分・日の制限表示が混同されないことを確認。変更したFlutter実装と通信テストの静的解析も問題なし。実Difyへの課金通信・本番デプロイは未実施。

この修正の反映：

```sh
firebase deploy --only "functions:tabisaki:prepareTransportOptimization,functions:tabisaki:optimizeTransportItinerary"
```

Firestoreルール・インデックス・registerAiTripの再デプロイはこの容量修正には不要。Flutterの文言変更を反映するにはアプリを再起動・再ビルドする。


## 2026-11-13：実ログの容量超過を修正

### 確認した原因

既存Functionsの診断ログを読み取り、交通データが **24,307,350文字・24,360,940 bytes**、上限が2,000,000文字・4,000,000 bytesで拒否されていることを確認した。回数制限ではない。前回の上限引き上げだけでは足りなかった。また、報告された「交通データの容量または利用回数の上限に達しました」は現在のソースには存在しない旧Flutterの表示文言。`flutter run` のアプリも停止・再起動する必要がある。

### 今回の修正

- `prepareTransportOptimization` で交通ネットワーク軽量化を既定で有効化。従来は未設定だと無効だった。falseの明示指定だけ診断用に無効化する。
- 矩形や上位N件で削除せず、登録接続の連結成分と緩和した時間到達可能性を使用する。
- 訪問済み集合（最大3施設、8状態）を使い、必須観光地で指定された滞在時間を過ごして期限までに到着できる可能性のある辺を保持する。全訪問順序を許容する。
- 徒歩・乗換バッファ・乗降制約・営業時間は除去判定では緩和する。実際の検索条件より広い経路集合にして、合法な経路を除去しない。同一便の連続辺、transferの禁止・便指定・路線指定、元の順序、ID、警告、表示メタデータは保持する。
- 滞在時間が到達可能性に影響するためキャッシュキーへ追加し、キーの版も更新した。
- 4 MB未満でも2,000,000文字の制限で止まる長時間・1施設のケースを確認したため、文字数上限は4,000,000へ整合。バイト上限は4,000,000のままで増やしていない。

### オフライン検証

以前に取得したローカルのGTFSスナップショット（4,230停留所・9,105便）を使用し、本番へDifyリクエストを送らず検証した。実際に失敗した利用者の入力そのものの再現ではない。

| 条件 | 軽量化前bytes | 軽量化後bytes | ローカル検索結果 |
| --- | ---: | ---: | --- |
| メロード往復（11/13、既存サンプル条件） | 8,946,656 | 37,347 | 一致 |
| メロード→石炭博物館→札幌（11/1、既存サンプル条件） | 15,183,106 | 77,840 | 一致 |

逆順、JR・バス乗換、日跨ぎ、営業時間外、便なしを含む7ケースで、既存ローカルrouterの結果、時刻、乗換、徒歩、要確認状態が一致。[全結果](transport_preparation_default_pruning_verification.json)。80通りの生成小規模ネットワークでは、緩和条件で可能な全経路を総当たりし、必要な辺が1つも除外されないことを比較した。Difyの実コード・実応答との一致は未検証。

札幌駅の公開登録の接続先13件を使った別の容量評価（同スナップショット、11/13、8:00〜18:00）では2施設のデータが552,877 bytesになった。1施設の広い時間窓では3,666,021 bytesになり、4MB以下だが従来の200万文字では止まることも確認した。これが文字数側を400万へ揃えた理由。

### 徒歩時間が未登録のときの入力

公開登録の札幌駅には13件の接続先があるが、すべてwalkingMinutesが未登録だった。従来UIは確認チェックだけではこの値を補えず、容量問題を解消しても有効な出発接続を送れなかった。

徒歩時間が全て未登録の地点には、「利用する駅・バス停」と「確認した徒歩時間」の入力を追加した。利用者が乗り場自体を出発・帰着地点とする場合は0分を入力できる。勝手に0分や推定値を入れず、指定された接続先だけを今回の入力として使う。Firestoreの登録値は更新しない。
出発地・帰着地・訪問先のいずれかに確認済み接続が無い間は、Difyへ送信せずその地点を案内する。未登録の接続先を架空に追加することもしない。

### 反映

```sh
firebase deploy --only "functions:tabisaki:prepareTransportOptimization,functions:tabisaki:optimizeTransportItinerary"
```

`TRANSPORT_OPTIMIZER_PRUNE=false` を以前設定した環境では、それを削除するかtrueへ変更してからデプロイする。容量の環境変数を明示している場合も、現在の400万文字・4MBに合わせる。

Flutterは実行中の `flutter run` を q または Ctrl+C で終了し、同じデバイス・起動オプションで再実行する。手動入力を含む新画面とエラー詳細表示を反映するため、ホットリロードだけでなく停止・再起動する。

Firestoreデータ更新・ルール変更・本番デプロイ・実Dify呼び出しは今回実行していない。公開された札幌駅レコードと既存のFunctions診断ログの読み取りのみ行った。

最終検証：Functions 100件、Flutter関連36件が成功。変更したFlutter実装・通信／画面テストの静的解析も問題なし。


## 2026-11-13：接続エラーのログ調査とDify入力型の修正

既存ログでは、日本時間11/13の00:26:27→00:26:29、00:29:00→00:29:02の2件がdispatched→uncertainとなっていた。生成されたJSONはそれぞれ389,507 bytesと577,997 bytesで、容量超過ではなかった。Flutterへ返したCallableのHTTPコードは503。ただし当時のログはDifyが返したHTTPコードを記録していないため、「Dify自身が503を返した」とは断定できない。

利用者の明示許可を得て、登録済みSecretをメモリ内だけで使い、DifyのGET /info・GET /parametersのみ読み取った。両方HTTP200で、アプリ名TABISAKI_Transport_Optimizer、mode=workflow、必須入力transport_dataの型が**json_object**と確認できた。Workflow・LLMの実行、Dify設定変更、キーの保存・表示は行っていない。[設定取得API](https://docs.dify.ai/en/api-reference/applications/get-app-parameters)

既存Functionsはtransport_dataを文字列としてPOSTしていたため、公開入力型との不一致が接続失敗の有力な原因として特定された。Functions→Difyの境界だけ、検証済みのJSONオブジェクトを送信するよう修正した。Flutter→Functionsの契約と全交通データの値は変更していない。

```json
{
  "inputs": { "transport_data": { "schemaVersion": 1 } },
  "response_mode": "blocking",
  "user": "認証UIDから生成した識別子"
}
```

上の例のtransport_dataは構造説明用の省略で、実際には検証済みのplaces/stops/routes/agencies/instances/segments/transfers等をすべて含む。

HTTP失敗ではDifyのHTTPステータスだけを安全なdetailsへ追加し、FunctionsログにerrorCode/httpStatusを記録する。本文・キー・巨大JSONは記録しない。Flutterも入力拒否などのHTTPコードを表示する。自動リトライは追加していない。文字列入力の別環境に戻す場合だけDIFY_TRANSPORT_INPUT_TYPE=stringを明示可能。現在の公開Workflowでは既定のjson_objectを使用する。

Functions全102件、Flutter関連37件がモックで成功。実Workflowの成功までは未検証。本番デプロイ・既存uncertainロックの解除はしていない。過去の要求についてはDify側の実行履歴を確認し、未実行または失敗が確定してから運用者が復旧する。入力型の推測だけでロックを解除しない。

この修正のFunctions反映は次の1関数のみ。

```sh
firebase deploy --only "functions:tabisaki:optimizeTransportItinerary"
```

FlutterのHTTP詳細表示も使う場合はアプリを停止・再起動する。DifyのCode②が文字列専用のjson.loadsを実装している場合は、JSONオブジェクトも受け取れる必要がある。Code②の実コードは今回の設定読み取りでは取得していないため、そこまでの適合性は未検証。


## 2026-11-13：AI作成UIの整理

実装ファイル：`lib/screen/itinerary/widgets/ai_trip_panel.dart`（条件シートとOutlinedButton）、`ai_transport_card.dart`（区間カード）、`itinerary_editor.dart` / `itinerary_transport_sheet.dart` / `bookmark_timeline.dart`（配置と自動遷移）、`lib/model/ai_trip_draft.dart`（登録情報と泊数）、`ai_trip_segment.dart`（区間への投影）。`Experience.visitInfo`は旅程保存時だけシリアライズし、既存の観光地マッチング用カードJSONを変更しない。

到着地の独立保存・地図表示と、シートの高さ変更時にレイアウト中の再描画が発生しない調整も含む。古い旅程の読み込みと、旧形式のAI往復提案の有効性判定は維持する。

Functions側は3日間の期限検証、登録済み徒歩値の使用に対する未確認フラグ、営業時間の仮定を保存結果の警告に引き継ぐ処理を変更。1旅程1回の予約・Secret・Firestoreルールは変更していない。以下の反映が必要（この作業ではデプロイしない）。

```sh
firebase deploy --only "functions:tabisaki:prepareTransportOptimization,functions:tabisaki:optimizeTransportItinerary"
```

Flutterは停止してから同じ起動条件で`flutter run`を再実行する。Firestoreルール/インデックスの追加デプロイや既存データの更新は今回不要。Dify/LLMの実通信は実施せず、モックで生成・失敗・自動遷移・表示・編集後の無効化を検証する。


今回の検証：関連Flutter 70件成功（AI作成11件、通信、出発/帰着、徒歩、時刻連動、地図、登録営業時間、ホーム、アカウント、有料列車選択）。Functions 104件成功。静的解析は変更ファイルで指摘なし。日本語フォント・アイコンを読み込んだ390px幅の描画と、320px幅の入力操作も確認した。

全体テストは直近の実行で175件成功・10件失敗・6件スキップだった。失敗には交通シートの2段階snapを期待するテスト（現状は3段階）、main未定義の`ai_matching_api_test.dart`、チャット・体験追加・マッチング画面の表示期待の不一致が含まれる。また単独の手動交通シートテストでProviderScopeを必須にしてしまう問題を検出し、AI表示を任意のWidgetとして編集画面から渡す構造に修正した。この修正後、有料列車選択を含む上記関連70件が成功した。全体テストの全件成功は主張しない。


## 2026-11-14：5タブ化と旅程ごとの作成制限撤廃

観光地のハートは旅行計画から独立した共通のお気に入りに保存する。旅程入力で選択した観光地だけを既存の手動編集・AI作成へ渡す。新しい検索やお気に入りの保存・解除で既存の旅程を上書きしない。

AIの成功状態を利用済みロックとして扱わず、新しい操作IDで同じ旅程を再生成できる。処理中・結果不明の排他、要求ごとの成功結果の再利用、既存の日次・分単位のレート制限は維持する。前回の成功結果と失敗した新しい要求を照合し、古い結果を新しい要求の結果として採用しない。

Flutterの変更に加え、`registerAiTrip`と`optimizeTransportItinerary`の再デプロイが必要。Firestoreルール・インデックス・Dify Workflowの変更は不要。生成履歴はAdmin SDKだけで保存し、クライアントは従来の旅程ドキュメントを購読する。

```sh
firebase deploy --only "functions:tabisaki:registerAiTrip,functions:tabisaki:optimizeTransportItinerary"
```

本変更では本番デプロイや実Dify Workflowの実行は行わない。

検証：Flutter全体は188件成功・3件失敗・6件スキップ。残る失敗は変更前から記録されている交通シートのsnap期待2件と、main未定義の`ai_matching_api_test.dart`。新しい導線・保存の移行・AIの再作成・文字拡大のテストは成功。Functions全104件と標準Webビルド（Firebaseプラグイン登録チェック付き）も成功し、日本語フォントを読み込んだ画面描画を確認した。
