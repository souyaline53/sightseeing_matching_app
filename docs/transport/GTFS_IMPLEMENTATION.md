# GTFS交通基盤の実装・導入メモ

本番へのデプロイ、ルール公開、交通データの削除・大量更新は実施していません。既存の未コミット変更を保持して実装を追加しています。調査はリポジトリとローカルエミュレーターで行い、本番FirestoreのレコードやFirebaseの契約プランは未確認です。

## 既存環境と再利用

Flutterの `lib/model/transport.dart`、交通Repository、管理者フォーム、観光地の `accessStops`、C案の旅程編集画面を再利用。既存の交通マスターはルート直下の6コレクション。既存Functionsは自治体ユーザーの権限変更、Storageは画像保管に利用。Firebaseプロジェクト設定は `sightseeing-matching-prototype`。管理者判定は認証済みトークンのメール `nichi-ka@nichi-ka.com` と `email_verified=true` をサーバー・ルールの両方で確認。旅程はFirestoreではなく端末のSharedPreferencesに保存されており、サーバーから全参照を列挙できません。

## スキーマ

```text
Storage: transport_imports/{adminUid}/{feedId}/{uploadId}.zip  管理者専用・上書き禁止
Firestore:
  transport_feeds/{feedId}
    feedId, publisherName, publisherUrl, version, timezone, validFrom, validTo,
    importedAt, sourceFilePath, checksum, activeVersionId, importStatus, importSummary
    versions/{ZIPのSHA-256}
      status: preview | invalid | importing | ready | failed
      preview: 件数・有効期間・差分・エラー・警告・原本パス・比較した有効版
      createdBy, createdAt, importStartedAt, importedAt, error
      transport_agencies/{正規化ID}
      transport_routes/{正規化ID}
      transport_stops/{正規化ID}
      transport_trips/{正規化ID}
      transport_services/{正規化ID}
      transport_fares/{正規化ID}
      transport_patterns/{パターンSHA-256}
      transport_passes/{レコードSHA-256}
  transport_agencies/{既存ID}  手動データは既存のルート直下6コレクションを維持
  transport_routes/{既存ID}
  transport_stops/{既存ID}
  transport_trips/{既存ID}
  transport_services/{既存ID}
  transport_fares/{既存ID}
```

正規化IDは `feedId~base64url(元IDのUTF-8)`。区切り `~` はfeedId・base64urlのいずれにも含まれず衝突を回避。元のGTFS IDは文字列で別途保持。バージョンが変わっても同じfeedId・元IDなら同じ論理ID。異なる名前空間や同名停留所を統合しません。

- agency: 元agencyId、name、officialName（JP提供時）、website、timezone、phone、email、JP拡張情報。
- route: 元routeId、正規化agencyId、routeShortName、routeLongName、routeType、displayName、name。
- stop: 元stopId、name、location（GeoPoint）、latitude、longitude、locationType、parentStationId、platformCode、zoneId、実際の便から生成したrouteIds。
- trip: 元tripId、正規化routeId/serviceId、headsign、directionId、stopTimes、stopIds、firstDepartureMinutes、lastArrivalMinutes、firstStopId、lastStopId。stopTimesはsequence、arrival/departureのSecondsとMinutes、pickupType/dropOffType、乗降可否、timepoint。Minutesは表示互換用の切り捨て整数、Secondsが原時刻の正確な値。
- service: 元serviceId、startDate/endDate（既存互換validFrom/validTo）、weekdays、addedDates、removedDates。例外日を先に判定し、祝日を推測しません。
- fare: 元fareId、price、currency、paymentMethod、transfers、transferDuration、rules（routeId/originId/destinationId/containsId）、検索用originZones。
- pattern: routeId、directionId、stopIds。停留所順と乗降区分ごとに別レコードを生成し、複数パターンを統合しません。
- pass: kind=pass、attributes、rules。通常の片道運賃の読み込み対象にはしません。

GTFS由来の各レコードにfeedId、versionId、sourceType=gtfs、verificationStatus=unverified。手動データはsourceType=manual（旧officialも互換）、情報源URL・確認日・isActiveを保持します。

## 管理者の操作

1. 管理者メニュー → 交通管理 → **GTFSインポート**。
2. 安定したフィードID（例 `yutetsu`）を指定し、ZIPを選択。
3. 「アップロード・検証・プレビュー」。ZIPは直下に標準ファイル名、UTF-8、20MiB以内。展開後100MiB、1ファイル50MiB、100エントリ以内。ZIPパス・暗号化・圧縮方式・展開比・CRCを検証。
4. 事業者、有効期間、各件数、新規・更新・廃止候補、エラー・警告を確認。
5. 「内容を確認して登録へ」→ 確認ダイアログの「承認して登録」。ここで初めてマスターを保存します。

原本再ダウンロード時にSHA-256を再確認。BulkWriterの全結果と各コレクションの保存件数を検証した後、有効版ポインターをトランザクションで変更します。並行更新時は再プレビューが必要。同じ有効ZIPの再登録は重複作成しません。失敗版は残り、旧有効版と手動データは変更しません。処理中にプロセスが停止した場合、10分のリース経過後に再試行できます。

手動登録は事業者・停留所・路線・運行日・便・運賃を既存フォームから入力。路線・便一覧は事業者／路線選択後に100件ずつ取得。便は路線を事業者から選び、行先・運行日と停留所ごとの時刻・乗降可否・順序を入力。行の追加・削除と「上へ移動」が可能。保存は `saveManualTransport` が管理者権限・参照・時刻順序を検証し、stopIdsと停留所routeIdsを生成します。GTFSマスターの直接編集は不可。手動便は手動マスターの参照だけを使用します。無効化は「有効な情報」をオフにして保存。

観光地編集では最寄り停留所の行を追加し「事業者 → 路線 → 停留所から選ぶ」。GTFS／手動双方の候補を、名称・IDで絞り込み、ID・乗り場を確認して選択。複数行の登録が可能。同じstopIdの重複は保存時に拒否。徒歩不明は空欄→null。walkingDistanceMeters、isPrimary、accessNotes、情報源・確認日も保存。アクセス行には選択路線の制限を保存しないため、時刻表ではその停留所を通る他路線も候補になります。

## 検索・更新と参照

C案は既存RepositoryにGTFS検索結果を合流。選択停留所を含む便だけ取得し、sequence・乗降可否・運行日を確認。pickup/dropoff=2/3（連絡・相談が必要）は通常候補に出しません。区間運賃はJPY、路線と発着ゾーンの適合、一意の金額を確認できた場合だけ表示。contains_idを必要とする運賃や競合する運賃は「運賃未確認」。パスを片道運賃として扱いません。

更新でstop_idが維持されればaccessStopsの論理IDは継続。削除・ID変更時は名前で置換せず、候補がない／保存便を確認できない表示になり再選択を促します。旧版を物理削除しません。保存便には選択時のバージョンIDと時刻を保持し、有効版が変わると再確認を促します。

## サンプルの整理

新規フォームからsampleやgtfs由来の手動データは作成できません。旧レコードのsample値は削除承認まで読み取り互換を残し、実データを装わない表示を維持しています。

交通管理 → **旧サンプルの削除候補を確認**。サーバーがsourceTypeまたはverificationStatusのsampleだけを抽出し100件ずつ表示。名称・sample_接頭辞による自動判定はしません。本番の候補一覧はまだ取得していません。

**物理削除の実行UI/APIは未実装**。端末保存旅程の参照をサーバーから検査できないためです。承認後の削除には、候補の確定・バックアップ・観光地accessStopsと交通マスター参照の点検・端末旅程に対する再確認導線の確認が必要です。当面は手動編集で無効化できます。従来の `replace_transport_samples.mjs` は移行のためには実行しないでください。

## コストと転送量

- 交通管理の初期表示は手動事業者100件のみ。全便を取得しません。
- 事業者→agencyIdで路線、路線→routeIdsで停留所。GTFSのrouteIdsはtrips/stop_timesから生成。
- 時刻表はstopIdsのarrayContains検索、必要なサービス・停留所・路線だけ取得。運賃もoriginZonesで絞り込み。無関係な事業者の便は取得しません。
- GTFSのページ・マスターはバージョンパス単位でキャッシュ。最大128エントリ・JSON換算8MiBで退避。ポインターは取得ごとに確認し、有効版が変われば別キャッシュキーになります。開いた画面のFutureProviderは「情報を更新」で再取得します。
- リアルタイムリスナーなし。ページは100件。大きいstopTimes、fare.rules、運行例外配列、pattern.stopIdsのインデックスを除外。
- `GtfsRepository.fetchedDocuments` / `fetchRequests` はSDKへ要求した取得文書・要求数の開発計測用累積値（課金値ではない）。キャッシュヒットは増加しません。Rulesのget、空クエリ最小課金、index entries、SDKローカルキャッシュ等は別途Firestoreの利用状況で計測してください。
- 初回検索の概算はフィード文書F＋対象停留所を通る便T＋参照マスターM＋候補運賃Q。往復の停留所検索で同じ便を取得する場合があり、取得後IDで重複排除します。検索中の細かい並列化・日付での事前絞り込み・大規模データのバックグラウンド処理は今後の最適化対象です。
- インポート1版の書き込みは全正規化レコード数＋パターン＋パス＋管理情報。履歴を保持するので容量は版数に比例。差分プレビューは旧版のID文書を読むため、インポート時の読み取りは発生します。更新件数は同一IDの候補数で、内容の変更件数ではありません。

## Firebase設定と導入

Node.js 22、Functions v2（asia-northeast1、GTFSは1GiB／540秒／同時1処理）。プロジェクトのBlazeプラン、Cloud Functions/Cloud Run/Cloud Build/Artifact Registry、Storageバケット・サービスアカウントのFirestore/Storage権限、課金アラートを確認してください。実行・ビルド・コンテナ保管・Storage・Firestoreの費用が発生し得ます。プロジェクトの現在のプランは未確認です。[Functions導入](https://firebase.google.com/docs/functions/get-started)、[料金](https://firebase.google.com/pricing)。

承認後に適用する設定は `firebase.json`、`firestore.rules`、`firestore.indexes.json`、`storage.rules`、`functions/`。手動交通マスターもサーバー専用書き込みに変更したので、Functions・ルール・新Webを同じリリース単位で導入し、旧管理画面の書き込みが拒否される点を周知してください。既存の本番インデックス設定は先にエクスポート・比較し、意図しない削除を避けてください。今回デプロイコマンドは実行していません。

## 開発検証

```sh
node --test functions/*.test.js
node functions/validate_gtfs.js /path/to/gtfs.zip yutetsu --expect-yutetsu
# 個別txtの開発用ディレクトリも同じ引数で対応
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' firebase emulators:exec --only auth,firestore,storage --project demo-tabisaki-gtfs 'node functions/transport_emulator_check.js && node functions/transport_rules_check.js'
dart format .
flutter analyze
flutter test
flutter build web
```

GTFS Scheduleの定期便・fare-v1を対象とした実装です。[仕様参照](https://gtfs.org/documentation/schedule/reference/)。GTFS全拡張の完全な公式バリデーターではありません。agency_jpを保存、translationsは原本のみ、パスは専用モデルに保存。shapes/transfersなど未知の任意ファイルは警告して原本に保持。frequenciesは対象tripを通常の発車候補から除外し警告（頻度便の展開は未対応）。Flex、fare-v2、経路乗換検索、補正データUI、地図による停留所確認、巨大GTFSのタスク分割は未実装です。

徒歩・前の観光地の滞在終了・乗換余裕を自動検証する処理は既存C案にないため、乗車可能性は未確認と明示します。24時超は運行日基準で扱い、前運行日の深夜便を翌日の暦日検索へ合流する検索は未実装です。停留所は単一便ドキュメント700KB、ZIP容量等の上限を超えると安全に拒否します。

夕鉄バスの原本は今回の作業ディレクトリとチャット添付から取得できていません。**3路線・53便・290停留所・2,542 stop_timesの実データ検証は未実施**。上記CLIに原本を渡せば期待件数も検査できます。合成データとエミュレーターの通過だけでは、本番実データの受入完了とはしません。

## この作業の変更ファイル

サーバー: `functions/gtfs.js`（ZIP/CSV/GTFS）、`transport_import.js`（プレビュー・保存・切替）、`manual_transport.js`（手動保存・派生索引）、`sample_inventory.js`（削除候補）、`index.js`（Callable登録）、`validate_gtfs.js`（開発用検証）。

Flutter: `lib/repository/gtfs_repository.dart`、既存 `transport_repository.dart`、`lib/model/transport.dart`、`admin_transport_fields.dart`、管理画面の `gtfs_import_screen.dart`・`transport_stop_picker.dart`・`transport_sample_screen.dart`・`transport_admin_screen.dart`・`admin_fields_form.dart`、`lib/service/transport/transport_admin_api.dart`・`zip_picker*.dart`・`transport_search.dart`、C案の `itinerary_editor.dart`・`itinerary_transport_sheet.dart`。

設定・検証: `firebase.json`、`firestore.rules`、`firestore.indexes.json`、`storage.rules`、`functions/gtfs.test.js`、`transport_emulator_check.js`、`transport_rules_check.js`、`functions/test_support/gtfs_fixture.js`、`test/gtfs_transport_test.dart`、既存 `tool/check_cloud_emulators.mjs`、本書と交通README。上記以外の作業ツリーの変更は、この作業以前のユーザーの未コミット変更です。

検証結果（ローカル）: `dart format .` 実行、`flutter analyze` 指摘なし、`flutter test` 106成功・2スキップ、`flutter build web` 成功。Nodeテスト12成功。Firestoreエミュレーターのプレビュー隔離・切替・再登録・不正ファイル・原本改変・手動データ保持・手動マスター全種類・途中時刻・路線停留所索引・無効化・参照不正・サンプル新規禁止が成功。Auth/Firestore/Storageルール検証で非管理者・未確認管理者・全クライアントの交通マスター書き込み拒否、旧版非公開、有効版公開、原本の管理者限定・上書き拒否が成功。本番コストの実測と実データによるブラウザー一連操作は未実施です。
