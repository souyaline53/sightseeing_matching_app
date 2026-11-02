# GTFS交通基盤：txt原本＋Storage配信方式

## 現在の構成

GTFSはUTF-8の`.txt`ファイル一式だけを受け付けます。ZIP対応は削除しました。GTFSの各行・各便をFirestoreへ展開しません。

| 保存先 | 内容 |
|---|---|
| Storage・管理者専用 | txt原本一式、削除前バックアップ |
| Storage・公開読み取り | 圧縮した停留所索引、路線一覧、路線別停留所・運行パターン、便のページ、運賃ゾーン別データ |
| Firestore | 有効版・公開待ち版・配信マニフェスト情報・検証結果、手入力交通マスター、観光地accessStops |
| 端末 | 必要な圧縮ファイルのメモリ／永続キャッシュ |

管理者認証、GTFS解析・参照検証、公開の承認、手入力編集、C案の時刻表表示は従来実装を再利用しています。手入力はFirestoreの既存6コレクションを維持し、GTFSと同じモデルに読み込んで検索結果へ合流します。GTFSの更新が手入力データを削除・上書きすることはありません。

## データ構造

```text
Storage:
  transport_imports/{adminUid}/{feedId}/{uploadId}/*.txt    原本・非公開・上書き禁止
  transport_data/{feedId}/{versionId}/
    manifest.json                                       全ファイルのSHA-256・容量
    catalog.json.gz                                     事業者・路線メタデータ
    stop-names.json.gz                                  出発地名検索用の軽量一覧
    stops/{停留所IDのSHA-256先頭2桁}.json.gz             停留所マスター・路線対応
    routes/{路線IDのSHA-256}/stops.json.gz               停留所・方向別パターン・便ページ索引
    routes/{路線IDのSHA-256}/trips-{ページ}.json.gz       便・対応する運行カレンダー
    fares/{出発ゾーンのSHA-256先頭2桁}-{ページ}.json.gz   運賃と適用ルール
    passes/{ページ}.json.gz                             パス情報（片道運賃検索には使用しない）
    ids/{種別}-{ページ}.json.gz                         更新差分用の論理ID一覧
  transport_backups/{実行日時}/samples.json              削除前バックアップ・非公開

Firestore:
  transport_feeds/{feedId}
    feedId, publisherName, publisherUrl, version, timezone, validFrom, validTo
    activeVersionId, checksum, sourceDirectory, importStatus, importedAt, importSummary
    distribution: {formatVersion:2, manifestPath, manifestChecksum, manifestBytes,
                   totalBytes, objectCount, platformLabels:{path,checksum,rawBytes,bytes}}
    pendingVersionId, pendingDistribution                公開前の準備時のみ
    versions/{versionId}
      status: preview | invalid | importing | prepared | ready | failed
      formatVersion, preview, distribution
      createdBy, createdAt, importStartedAt, preparedAt, importedAt, error
  transport_agencies/{id}                                手入力
  transport_routes/{id}                                  手入力
  transport_stops/{id}                                   手入力
  transport_trips/{id}                                   手入力
  transport_services/{id}                                手入力
  transport_fares/{id}                                   手入力
```

versionIdはファイル名と各ファイルの内容のSHA-256から生成します。選択順が違っても同じ一式なら同じ版になります。原本も検索データも不変のパスへ保存し、全保存ファイルを再ダウンロードしてチェックサムを照合してから有効版を切り替えます。失敗した場合は旧有効版を維持します。同一原本の再処理で変換形式を変える場合は、既存配信ファイルを上書きせず、配信形式・版管理の移行が必要です。

論理IDは `feedId~base64url(元GTFS IDのUTF-8)`。元IDの文字列表記・先頭ゼロは別フィールドにも保持します。IDが継続すれば、版が変わってもaccessStopsの参照は継続します。ID変更を停留所名で推測して置き換えることはありません。既存のFirestore方式のフィードに対する読み取り互換も残しています。

## 管理画面のアップロード

1. 管理者メニュー → 交通管理 → **GTFSインポート**。
2. 初回に固定のフィードIDを決め、更新時も同じIDを使います。
3. 「アップロードする標準ファイル名の一覧」を確認します。事業者ごとにファイル名が違う場合は、内容を確認してから手元で標準名へ変更してください。
4. 同一事業者・同一ダイヤ版の`.txt`一式をまとめて選択します。
5. 「アップロード・検証・プレビュー」。件数、有効期間、同一IDの更新候補、新規・廃止候補、エラー・警告を確認します。
6. 確認ダイアログで承認すると、サーバーが圧縮配信データを生成・保存・検証し、有効版を切り替えます。

| 標準ファイル名 | 用途 |
|---|---|
| agency.txt | 必須：交通事業者 |
| stops.txt | 必須：停留所 |
| routes.txt | 必須：路線 |
| trips.txt | 必須：便 |
| stop_times.txt | 必須：途中停留所の発着時刻・停車順 |
| calendar.txt / calendar_dates.txt | 少なくとも一方が必要：曜日・期間／例外日 |
| fare_attributes.txt / fare_rules.txt | 運賃／適用路線・ゾーン |
| feed_info.txt | 配信元・有効期間。translations.txt使用時は必須 |
| agency_jp.txt | 日本向け事業者情報 |
| routes_jp.txt / office_jp.txt | 日本向け路線・営業所。原本保管 |
| translations.txt | 翻訳。原本保管 |
| pass_attributes.txt / pass_rules.txt | 定期券・フリーパス。片道運賃と別管理 |
| shapes.txt / transfers.txt | 原本保管・未対応警告 |
| frequencies.txt | 対象便は通常の時刻表候補から除外・未対応警告 |

1ファイル50MiB、合計100MiB、最大100ファイル。空ファイル、重複名、パスを含む名前、非UTF-8、ZIPは拒否します。未知の任意txtは警告し原本を保持します。列名やIDをファイル名に合わせて変更しないでください。

## 手入力・最寄り停留所・C案

手入力は既存の事業者・停留所・路線・運行日・便・区間運賃フォームから登録します。保存は `saveManualTransport` が管理者認証・参照・時刻順序を検証。便の途中停留所の追加・削除・順序変更、時刻・乗降可否、運行例外日、無効化、情報源URL・確認日を扱います。停留所と路線の対応は実際の便から再生成します。GTFSの直接編集はできず、手入力便は手入力マスターを参照します。

観光地のaccessStopsは「事業者 → 路線 → 停留所」でGTFS・手入力双方を探せます。事業者を開いても便を読み込みません。路線選択時は停留所とパターンだけを取得。同名停留所もIDと乗り場を表示して区別します。複数登録、徒歩時間null、距離、主なアクセス、補足、確認日・情報源を保存できます。同一stopIdの重複登録は拒否します。

C案は選択停留所の索引から実際に通る路線を取得し、対象停留所を含む便ページだけを読み込みます。途中停留所間の順序・乗降可否・旅行日の運行を確認。秒精度と24時超を保持します。乗降区分2/3の要連絡便は通常候補から除外。運賃は路線・発着ゾーンが一致し、JPYの一意の料金が得られる場合だけ表示し、contains_id等を解決できない場合は「運賃未確認」。定期券やパスは候補運賃に使用しません。

保存便には選択時の版と時刻を保持し、版の変更や便・停留所の廃止時は再確認・再選択を促します。選択時に使った路線にアクセスを限定せず、その停留所の他路線も候補に含めます。

## 同名停留所・方向別乗り場の一括登録

観光地編集の「最寄り駅・バス停」にある **停留所を探して乗り場をまとめて追加** を使用します。事業者・路線を選択すると、同一フィード内の同名乗り場を表示上だけまとめます。グループを開いて **すべての乗り場を選択**、または個別チェックで選び、**選択したN件を登録** を押します。

- 元のstopId・座標・乗降区分は統合しません。名前だけで同一IDにしたり、ID末尾100/200を上り・下りと推測したりしません。
- 各乗り場の案内は実際のtripsの行先とstop_timesの乗降区分から生成します。行先がない場合はその便の終着停留所名を使います。降車専用の場合は到着元を表示します。
- 選択時はID・方向・乗り場・座標と、乗り場間の直線距離を確認できます。300mを超えて離れた同名候補には注意文を表示します。距離は徒歩経路の長さではありません。
- 両方選択してもaccessStopsは各IDの別レコードです。新規の徒歩時間・距離はnull、主なアクセスはfalse。管理者が個別に入力・指定できます。既存IDは重複追加せず、既存の徒歩時間や主なアクセスの設定も保持します。
- 表示用のstopName・stopDestinations・platformCodeだけを追加保存し、選択路線に利用可能な便を限定しません。C案の検索は引き続き正規化IDと実際の便・停車順・乗降可否・運行日で判断します。
- C案のアクセス詳細は「夕張高校／新夕張駅前方面」のように表示します。保存した旅程の控えにも名称・行先を保持し、旧旅程では従来のID表示へフォールバックします。

方向情報は `distribution.platformLabels` が参照する内容ハッシュ付きの小さなgzipファイルです。夕鉄バスは2,000 bytes、北海道中央バスは37,559 bytes。管理画面で全便を読む必要はありません。既存版への追加では、時刻表マニフェストとstopId・有効版を変えずに別の不変ファイルを追加します。今後のインポートでも自動生成します。案内は選択の補助で、当日の運行や乗車可否を保証するものではありません。旧フィードや手入力で案内がない場合は「方向情報未確認」としてID・位置で区別できます。

今回の変更はFunctions（importTransport）とWebへ公開済み。ルール変更と停留所・便の削除・統合は行っていません。夕張高校・南清水沢の実際の行先、明示的な一括選択と個別解除、徒歩null・既存値保持、両方向の便検索、既存時刻表マニフェストの不変性を確認しました。

## キャッシュ・転送量・権限

- 圧縮gzipファイルは路線・便ページ・停留所索引・運賃出発ゾーンに分割。便ページは原則128便またはJSON約512KiB以下。全事業者・全便を毎回取得しません。
- SHA-256を照合してから展開。メモリキャッシュは圧縮データ8MiB、永続キャッシュは512KiB以下のファイルを最大128個（最大約64MiB）。WebはCache API、ネイティブはアプリキャッシュ領域。キャッシュ利用不可時は通常取得します。
- キャッシュキーは配信パス・版・チェックサムを含み、更新時の別版と混在しません。同時取得をまとめ、改変キャッシュは破棄・再取得します。
- 開いた画面は「情報を更新」でフィードの有効版を再確認。取得済みファイルを再利用します。画面を閉じた後も永続キャッシュを再利用できます。端末からキャッシュが消去された場合は再ダウンロードします。
- `GtfsRepository.fetchedDocuments/fetchRequests` はFirestore取得の概算計測、`GtfsRepository.loader.requests/downloadedBytes/cacheHits` はStorage取得計測です。課金上の最小読み取りやRulesの内部読み取りは別途です。
- raw原本・バックアップは管理者限定。公開する検索データは交通情報のみ。配信ファイルは公開getのみで、一覧取得・クライアント書き込みは禁止。旧バージョンの公開配信ファイルは保持されます。
- 交通マスターのクライアント直接書き込みは禁止し、手入力もGTFSもサーバーで権限を再確認。Storage原本の作成は確認済み管理者本人のフォルダ・txt・容量制限を適用し、更新・削除を禁止しています。

Storageでも容量・操作・転送の費用は発生します。今回、GTFSマスターの大量Firestore書き込みはなく、各フィードと版の管理情報だけを書き込みます。約20万のstop_timesをFirestoreの20万文書として保存する構成ではありません。

## 今回の実データと本番作業（2026-11-01）

札幌市交通局はユーザー指示で対象外とし、`docs/transport/gtfs_sapporo1` を削除しました。アプリ・Firebaseには取り込みません。

| フィードID | 事業者 | 路線 | 停留所 | 便 | stop_times | 原本容量 | 圧縮検索データ容量 |
|---|---|---:|---:|---:|---:|---:|---:|
| yutetsu_bus | 夕鉄バス | 3 | 290 | 53 | 2,542 | 1,028,648 bytes | 516,859 bytes |
| hokkaido_chuo | 北海道中央バス | 185 | 3,863 | 8,639 | 200,801 | 20,720,795 bytes | 7,264,691 bytes |

両事業者とも14ファイルを本番Storageへ保存し、全検索ファイルを照合済み。**2026年11月1日に本番公開・有効化済み（ready / activeVersionId）です。** 接続先は `sightseeing-matching-prototype`、Storageは `sightseeing-matching-prototype.firebasestorage.app`（US-EAST1）。今後の更新も、保存・検証完了後に有効版を切り替えます。

原本は再処理と実データ回帰テストに使用するため、夕鉄・中央バスのローカルtxtは保持しています。アプリのWebビルドにdocsは同梱されません。

ユーザーの許可により、sourceTypeまたはverificationStatusがsampleの交通マスター11件を削除しました。本物の交通マスターからの参照はなし。観光地 `lake`・`melon`・`rail` から対応する架空停留所のaccessStopsだけを取り除き、観光地本体や他フィールドは保持しています。実在の最寄り停留所は管理画面で選び直してください。名前だけで自動対応はしていません。

削除前バックアップ:
- ローカル: `.local-backups/transport-samples-2026-11-01T08-53-24-822Z.json`
- 非公開Storage: `transport_backups/2026-11-01T08-53-24-822Z/samples.json`

端末保存旅程に残るサンプル選択は、次回の交通情報更新で再選択が必要な状態になります。テスト専用の `sample.json` は回帰テストで使うため保持しています。新しいサンプルの本番登録は禁止しています。

## 導入・検証

Node.js 22 / Functions v2、asia-northeast1、GTFS処理は1GiB・540秒・同時1処理。既存プロジェクトのBlaze・Storage・Functions権限と課金アラートを確認してください。[Storageダウンロード](https://firebase.google.com/docs/storage/flutter/download-files)、[料金](https://firebase.google.com/pricing)。

本番公開時には、Functions、Firestoreルール、Storageルール、Webアプリを同じ変更として反映します。Firestoreルールの新しいコード変更はありませんが、前回追加したtransport_feeds読み取り権限が本番未反映だったため、今回あわせて公開しました。公開前は認証なしのフィード一覧・配信マニフェストがHTTP 403でしたが、公開後は読み取り可能です。原本txtは引き続きHTTP 403で保護され、非管理者のCallable登録要求も拒否されます。ユーザーから今回の公開承認と、今後この作業に必要なデプロイ・ルール公開を追加確認なしで進める許可を受けています。本番へのFunctions・Firestoreルール・Storageルール・Webの反映と2事業者の有効化は完了しました。

```sh
node --test functions/*.test.js
node functions/validate_gtfs.js docs/transport/yutetsu_bus yutetsu_bus --expect-yutetsu
node functions/validate_gtfs.js docs/transport/hokkaido_chuo hokkaido_chuo
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' firebase emulators:exec --only auth,firestore,storage --project demo-tabisaki-gtfs 'node functions/transport_emulator_check.js && node functions/transport_rules_check.js'
dart format .
flutter analyze
flutter test
dart run tool/build_web.dart
node tool/check_web_release.mjs --local-build
```

本番保守ツールはFirebase CLIの既存OAuthログインを使用し、認証情報をファイルやログへ書き出しません。
- `node functions/inspect_transport.cjs`：接続先・フィード・サンプル候補の読み取り。
- `node functions/stage_transport_feeds.cjs --apply`：検証・txt原本と配信データの保存・照合、公開待ち登録。
- `node functions/stage_transport_feeds.cjs --activate`：Functions・ルール・Webの公開確認後、準備済みデータの有効化。
- `node functions/cleanup_transport_samples.cjs`：サンプル削除計画。`--apply`はバックアップ・更新時刻の競合チェック後、明示sampleレコードだけを削除。本物から参照されるマスターは保持し、架空停留所の観光地参照だけを除去します。

テスト: `dart format .` 実行、`flutter analyze` 指摘なし。サーバー15成功。Flutter112成功（本番接続4件は別途実行して成功）、Webビルド成功。Storageのみへの登録、GTFSのFirestoreマスター文書ゼロ、同一一式の重複防止、不正原本・途中改変・参照不整合の拒否、更新時の旧配信ファイル保持、手入力索引、公開／非公開／書き込み拒否をエミュレーターで確認。Dart側では同じ生成済みgzipを使い、事業者・路線・停留所の閲覧で便ページを取得しないこと、途中乗降・運行日・ゾーン運賃、永続キャッシュ、改変検出を確認しました。

## 本番公開後の検証

公開URL: https://sightseeing-matching-prototype.web.app

本番のHTML・JavaScript配信、Firestoreの有効版情報、Storageマニフェスト、ブラウザー用CORS応答を確認済み。新規Functions `importTransport`・`saveManualTransport`・`transportSampleInventory` を公開し、既存 `setMunicipalityUser` も更新しました。

`flutter test --dart-define=GTFS_LIVE_TEST=true test/gtfs_live_test.dart` の読み取り専用検証4件が成功しました。通常のテスト実行では本番接続4件をスキップします。

- 夕鉄バス：実際の途中停留所間で候補1件、検証中のStorage取得9回・60,305 bytes。
- 北海道中央バス：実際の途中停留所間で候補12件、検証中のStorage取得11回・235,904 bytes。
- 両方とも同じ区間の再検索による追加通信0回、原本txtの非公開、非管理者による登録拒否を確認。測定値は今回選んだ区間の結果で、任意区間の上限・課金額を示すものではありません。
- 乗車専用の途中停留所しかない急行路線は、途中降車候補から正しく除外されます。

公開前ルールの退避先は `.local-backups/pre-gtfs-release-2026-11-01T09-01-57-535Z/`。公開用ビルド・サーバーテスト15件・静的解析は再確認済みです。管理者ログインでのブラウザー操作を自動化した検証は行っていません。

## 主な変更ファイルと制約

サーバー: `transport_stop_labels.js`、`update_stop_labels.cjs`、`transport_bundle.js`、`transport_import.js`、`gtfs.js`、`validate_gtfs.js`、実データ・配信・エミュレーターテスト、今回のアップロード／バックアップ付き削除ツール。

Flutter: `stop_selection.dart`、`stop_group_options.dart`、`transport_stop_picker.dart`、`admin_fields_form.dart`、`gtfs_import_screen.dart`、`txt_picker*.dart`、`gtfs_txt_file.dart`、`gtfs_bundle_reader.dart`、`gtfs_repository.dart`、`transport_repository.dart`、`transport_stop_picker.dart`、`gtfs_asset_loader.dart`、`asset_cache_*.dart`、`gtfs_bundle_test.dart`。設定は `pubspec.yaml/lock` と `storage.rules`。

完全なGTFS全拡張バリデーターではありません。GTFSの補正編集UI、Flex・fare-v2、頻度運行の時刻展開、翻訳の画面反映、停留所の地図確認、徒歩経路・滞在終了時刻の自動算出は未実装です。最大3回の乗換検索・乗換余裕の判定・前運行日の深夜便は末尾の乗換検索に実装しました。乗車可能性が確定しない場合は既存UIで未確認と表示します。手入力の配信データ自動生成はせず、Firestore経由で共通モデルへ合流します。巨大な単一レコードや配信ファイルは上限を超えたら旧版を保持して拒否します。


## WebだけFirebase読み込みが失敗した不具合の修正

2026年11月1日、公開Webアプリの実画面で観光地読み込み失敗を再現しました。iOSは正常でしたが、Webの生成済みプラグイン登録ファイルが古く、SharedPreferencesだけが登録され、Firebase Core/Auth/Firestore/Storage/Functionsの登録が欠落していました。ブラウザーではFirebase SDKの読み込み自体が始まっていませんでした。

修正はFlutter自身によるWeb登録ファイルの再生成とWebの再ビルド・再公開です。生成ファイルを手編集したり、Firebaseのデータ・権限ルール・APIキーを変更したりはしていません。ビルドスクリプト `tool/build_web.dart` はWebエントリポイントの生成キャッシュだけを無効化してからビルドします。`tool/web_build_guard.dart` が登録漏れと配信用JavaScript内のSDK初期化欠落を検出し、Hostingのpredeployでも不備を拒否します。

これまでのDart・HTTP中心の本番テストでは、コンパイル済みアプリの自動プラグイン登録を検証できていませんでした。今回追加した `tool/check_web_release.mjs` は新しいChromeプロファイルで実際の配信用アプリを起動し、観光地ホームの表示と、そのアプリが初期化したFirebase Web SDKによるFirestore・Storageの読み取りを確認します。Firebaseをテスト内で手動登録しません。CIにも公開前のブラウザー検証を追加しました。

起動用のHTML/JavaScript/Service Workerは毎回再検証するHostingヘッダーを設定しています。保存済みの旅程やログイン情報を消す変更はありません。Firebase初期化に失敗した場合はブラウザーのConsoleにも原因を出力します。


最終公開版では起動ファイルに内容ハッシュ付きURLを付け、HTMLと起動JavaScriptは毎回再検証する設定にしました。SDKが生成するService Worker移行用解除スタブの毎回登録は行いません。新規Chromeと、不具合を再現した既存Chromeプロファイルの両方で復旧を確認済み。保存情報の消去はしていません。ブラウザー内の実Firebase SDKで観光地と交通フィード2件、Storageの検索データを取得でき、通常テスト115件と公開前検査3件が通過しました。

## 同名500m以内・最大3回の乗換検索（2026-11-01更新）

2026-11-02から、旅程上部の日付と出発時刻を基準に直通・最大3回の乗換を自動検索します。乗換専用操作や最小乗換時間の選択は不要です（末尾の「出発時刻保存・候補一覧の統合」を参照）。上限はサーバーでも3回（4本）に制限し、4回以上の指定は拒否します。到着時刻と乗換回数のPareto候補を最大4件返し、全経路を列挙しません。検索期間は出発後48時間以内です。

### 同名停留所の扱い

- 名称が一致し、緯度経度から求めた直線距離が **500m以内（境界を含む）** の停留所同士を共通の検索候補にします。事業者・feedIdが異なる場合も対象です。名称はUnicode NFCと前後空白の除去だけで比較し、別名・部分一致・読みの類似では統合しません。
- GTFSのstopId・便・停車順・保存済みaccessStopsは変更しません。検索時に乗車側・降車側の候補を広げ、途中の乗換にも同名の近接乗り場を使用します。実際に利用する乗り場のIDと行先を結果・旅程に保持します。
- 座標不明・不正座標・500m超の同名・無効な停留所は自動接続しません。親駅や同一zoneだけでは接続しません。
- A-Bが400m、B-Cが400mでも、A-Cが800mなら直接同一扱いにしません。近接ペアを保持し、徒歩接続を連鎖させて遠方へ拡張することを防ぎます。管理画面の一括選択グループも、グループ内の最大距離を500m以内にします。検索側は直接の近接ペアを使うため、表示グループの境界でも500m以内の候補は検索できます。
- 別乗り場への自動接続は0分にしません。直線距離×1.3の迂回係数、歩速60m/分、余裕2分を使って分単位に切り上げ、最低3分を確保します。500mでは13分が目安です。これは実際の徒歩経路ではなく **推定** で、結果に「道路経路未確認」と表示し、経路全体をneedsReviewにします。
- GTFSまたは管理者による確認済みの必要時間・乗換禁止を自動接続より優先します。通行できない道路横断などは管理画面「⑦ 乗り場間の乗換接続」で、片方向ごとに **乗換不可・確認済み** として登録してください。確認済み接続を単に無効化した場合は、その明示設定が除外され、同名500mの推定接続が再び使われます。

出発可能時刻は、前の場所での滞在を終えて徒歩移動を開始できる時刻です。最寄り停留所までの徒歩時間が登録済みなら、その時間と、別乗り場を利用するための移動時間を加えて乗車可否を判定します。徒歩時間がnullなら参考候補とし、0分登録に置き換えません。降車後も同様に移動時間を加えます。乗車前・降車後の追加移動はaccessBefore/accessAfterに保存します。

### 検索・コスト対策

`functions/transport_router.js` は乗車回数ごとの最大4ラウンドで最早到着を求めます。途中停留所、同じstop_idへの再訪sequence、秒単位の時刻、乗降制限、路線の有効状態、calendar/calendar_dates、前運行日の25:xxなどを照合します。便・路線を指定する乗換ルールは直前の便ごとのラベルを保持して優先順位を判定します。頻度運行・車内継続乗車・日本標準時以外のフィードは引き続き未対応です。区間運賃・乗継割引も乗換結果では未確認表示です。

同一フィード内の近接ペアはGTFS取り込み時に生成します。異なるフィード間・手入力の近接ペアは、サーバーのネットワークキャッシュ生成時に一度だけ生成します。同名だけに対象を絞り、緯度順で500mの範囲に絞ってから距離を計算します。検索リクエストごとに全停留所同士の距離を計算しません。乗車地点ごとの接続元と各便の時刻範囲もキャッシュし、同一サービス日の運行判定を検索内で再利用します。

`searchTransportJourneys` は公開読取り用Callable（asia-northeast1、1GiB、60秒、同時1・最大2インスタンス）。クライアントから受け取るのは停留所ID・徒歩時間・旅行日・時刻・上限だけです。全時刻表や近接ペアを端末へ送りません。応答は最大4経路とその便・移動時間だけで、グループの全メンバーも返しません。

検索ごとのFirestore読取りは有効フィード情報と手入力revision（現在2フィードなら3ドキュメント相当）。Storageのgzip検索データ・手入力マスターはcold時または版/revision更新時に取得します。手入力保存のトランザクションでrevisionも更新します。Functionsのメモリーはインスタンス間で共有されません。3回への制限は探索・結果件数を抑えるもので、返却する候補が増える場合もあるため、個別検索の通信量が必ず減るという意味ではありません。画面を開いた際の直通時刻表・地図・写真・Webアプリ本体の通信は別です。

### スキーマと更新

```text
transport_feeds/{feedId}.distribution.routing
  path, checksum, bytes, rawBytes
transport_feeds/{feedId}/versions/{versionId}.distribution.routing
  同じ検索用ファイルを参照
transport_data/{feedId}/{versionId}/routing-{checksum}.json.gz [Storage]
  formatVersion:2, feedId, versionId, timezone
  stops: id, name, latitude, longitude, locationType, platformCode, parentStationId, zoneId
  sameNameConnections: [[stopIdA, stopIdB, distanceMeters, estimatedSeconds], ...]
  routes, services, compact trips, transfers
transport_transfers/{id} [Firestore、サーバー書込みのみ]
  name, fromStopId, toStopId, minTransferSeconds, transferType:2|3
  isActive, verificationStatus, sourceType, sourceUrl, sourceCheckedAt
transport_routing_state/manual [サーバー専用]
  revision, updatedAt
旅程のtransportSelections[].journey
  legs[]: trip/route/stop IDs, names, platform, sequence, serviceDate, versionId, seconds
  transfers[]: from/to IDs, required/available seconds, source, ruleIds, estimated, distanceMeters
  accessBefore/accessAfter: registered/actual platform movement and estimated flag
  queryDate, transferCount, endpoint walks, verificationStatus, usesEstimatedWalking, timetableChecked
```

旧formatVersion=1の読取りは互換性を維持します。そのフィードでは座標がないため近接接続を生成せず、データ更新待ちの警告を返します。新規取り込みはformatVersion=2の検索用データを保存・照合してから有効版を切り替えます。

既存の2事業者は `node functions/update_routing.cjs --apply` で検索用ファイルと参照情報だけを更新します。原本チェックサムと有効版の一致を確認し、既存のmanifest、停留所ID、便、accessStops、保存済み旅程は変更しません。旧検索ファイルも保持します。容量・objectCountの更新は有効な参照に対して冪等です。

選択経路は全便・乗換・版・運行開始日・徒歩推定をスナップショットとして保存し、しおりでも表示します。以前の単一便・5回乗換時代の控えも読取り可能で、編集画面では現在の3回上限に合わせた再選択を促します。

### 実データによる比較・検証

`node functions/benchmark_journeys.cjs --baseline=/tmp/tabisaki-router-before-500m.cjs` による同一端末・同一条件・warm実行5回の中央値。旧版モジュールは変更前に一時退避したものです。ネットワーク時間・cold startは含まず、本番の応答速度を保証する数字ではありません。

| 検索条件 | 旧5回・近接接続なし | 新3回・500m接続あり |
| --- | ---: | ---: |
| 札幌駅前／北口から | 約127ms | 約66ms |
| 夕鉄・乗り場片側のみ登録 | 約110ms・2回乗換 | 約59ms・直通 |

新規ネットワーク構築は約23ms、近接ペアは5,508方向分（双方向を含む）でした。新しい圧縮検索データは夕鉄30,758バイト、中央バス1,602,078バイトで、端末への検索時ダウンロードはありません。端末が送る検証条件のJSONは札幌1,053バイト・夕鉄251バイト、ローカル結果本文はそれぞれ約3.7KB・約2.0KB（本番APIの版情報・統計・HTTPヘッダー等は別）でした。

`dart format .`、`flutter analyze`（指摘なし）、`flutter test`（119成功・6スキップ）、サーバーテスト34件、Firestore/Auth/Storageエミュレーター、Webビルド成功。500mちょうど／501m、座標不明、別事業者、徒歩時間不足、3回成功／4回拒否、乗換禁止、遠方への連鎖防止、座標変更と無効化によるキャッシュ更新、保存互換と推定表示を確認しました。

追加・変更の中心は `functions/transport_nearby_stops.js`、`transport_routing_bundle.js`、`transport_router.js`、`transport_journey_api.js`、`transport_nearby_stops.test.js`、`benchmark_journeys.cjs`、`lib/model/stop_selection.dart`、`transport_journey.dart`、`lib/screen/itinerary/transport_journey_panel.dart`、管理画面の停留所グループ表示と関連テストです。Security Rulesの追加変更はありません。

検索方式の参考: [Round-Based Public Transit Routing](https://www.microsoft.com/en-us/research/publication/round-based-public-transit-routing/)、ルール仕様: [GTFS Schedule transfers.txt](https://gtfs.org/documentation/schedule/reference/#transferstxt)。

公開後の実測では、札幌発検索は送信1,053バイト・受信4,013バイト（2候補）、夕鉄の500m乗り場展開は送信251バイト・受信2,304バイトでした。いずれもJSON本文のみで、HTTP/TLS等は別です。本番サーバーの計算部分は約0.51〜0.66秒。公開Callableで4回指定の拒否・夕鉄の推定徒歩付き直通候補を確認しました。直通時刻表と乗換検索の表示も区別し、直通候補がないことを交通情報全体の未登録として表示しないようにしています。

Functions（searchTransportJourneys・importTransport・saveManualTransport）、検索用Storageデータ、Hostingの更新を完了しました。最終公開版をChromeで起動し、観光地・2フィードの読取りと、Web SDK経由の最大3回検索（2候補・計算約0.77秒）を確認済みです。既存の公開GTFS版・停留所ID・旅程は保持しています。


## 出発時刻保存・候補一覧の統合（2026-11-02）

旅程作成ページの日付の直下に出発時刻ピッカーを追加しました。初期値は08:00。`TripState.departureMinutes`（0〜1439、日付から独立した分数）を既存の旅程JSONに保存し、旧データは08:00として読み込みます。SharedPreferencesの既存ライブラリー形式version=1を維持し、日付・保存済み訪問順・交通選択を保持します。しおりにも出発時刻を表示します。

各区間は、保存した旅行日・出発時刻から直通と最大3回乗換を自動取得し、従来のカード×時刻表にまとめて表示します。別の乗換検索パネル、回数セレクター、最小乗換時間セレクター、検索開始ボタンは廃止しました。最小乗換時間は従来の3分を内部の既定値にし、登録済みルールと500m同名停留所の移動見積もりを引き続き適用します。IDや便IDは画面に出さず保存データに保持し、徒歩時間が不明な場合は徒歩行・注意書きを表示しません。内部の確認状態や元データは変更しません。

直前の区間を選択済みなら、その観光地への到着時刻以降に出発できる候補だけを表示します。到着09:00なら09:00ちょうどを含み、それより前を除外します。登録済みの降車後徒歩を到着に含め、乗車前徒歩が分かる場合は到達できる候補に絞ります。滞在時間は自動加算しません。直前が未選択なら保存した出発時刻（初期08:00）を使い、別の区間の選択を誤って流用しません。日付変更で無効になった古い選択も時刻基準に使いません。

### リクエストと候補キャッシュ

`itineraryJourneysProvider` は旅行日・保存した出発時刻・区間のaccessStopsをキーに候補を保持します。**直前の選択・到着時刻はキーに含めません。** 便の選択・変更・解除時は取得済み候補のローカルフィルターだけを変更し、再リクエストを行いません。日付・保存した出発時刻・区間の停留所条件を変えた場合、または「情報を更新」の明示操作で取得し直します。

新しい自動取得はCallableに `timetable:true` を指定します。出発時刻から24時間以内の最初の乗車を対象に、1時間ごとの早着候補を最大25時間帯分まとめて保持します。乗換・到着は従来の48時間以内。直通時刻表の候補もID・停車順・時刻で重複排除して一覧に統合します。これは全ての乗換経路・同一時間帯の全便を列挙するモードではありません。表示可能な候補がなくても、直前選択をトリガーに追加検索を繰り返しません。

候補プールはJSON配列をgzip+base64にして `journeyPool:{encoding,rawBytes,data}` で返し、アプリ側で復元します。既存の `journeys:[]` 応答との互換性を維持します。画面で使わない注意書きは表示しません。サーバー側でも現在のネットワーク版/revisionごとに最大32条件の検索結果を保持し、繰り返し計算を避けます。Firestore読取り・権限・GTFS保存方式は変更していません。

主な変更: `trip_plan.dart`、`trip_state.dart`、`transport_journey.dart`、`itinerary_transport_options.dart`、`transport_journey_repository.dart`、`itinerary_editor.dart`、`itinerary_transport_sheet.dart`、`transport_journey_panel.dart`（詳細表示のみ）、`plan_screen.dart`、`functions/transport_router.js`、`transport_journey_api.js`。サーバーの通常モードは従来どおり最大4候補で、既存クライアントと管理機能を維持します。

検証: `dart format .`、`flutter analyze` 指摘なし、Flutter121成功・6スキップ、サーバー36成功、エミュレーター成功、Webビルド成功。追加テストでは、旧データ08:00互換、日付と時刻の再保存、ピッカー入力、到着09:00の境界、直前便の変更・解除でもRPC回数が増えないこと、ヘッダー出発時刻変更時の新規取得、ID・徒歩不明注意書きの非表示、圧縮プールの復元とサーバーキャッシュを確認しました。

2026-11-02に検索FunctionsとHostingへ公開しました。公開APIの時間帯別取得は、札幌の例で17候補・送信1,070バイト／受信4,086バイト、夕鉄の例で送信268バイト／受信2,769バイト（いずれも本文のみ）。札幌の初回計算は約6.56秒、同条件のサーバーキャッシュ利用時は計算部分0msでした。メタデータ読取り・ネットワーク・cold startは別にかかります。候補をまとめるため初回の計算は従来より増えますが、便選択時の再リクエストをなくし、候補プールのgzip+base64圧縮で通信量を抑えています。公開前のChromeでも、実データ17候補のWeb SDK経由の取得・復元を確認しました。GTFS原本・有効版・ID・マスター・既存の保存旅程の削除や一括書換えは行っていません。

## 共通の最寄り停留所は「徒歩のみ」（2026-11-02）

A・BのaccessStopsが同じ正規化stopIdを1件以上共有する場合、旅程編集では便データ取得・検索Callableを呼ばず、「徒歩のみ」と表示します。空ID・無効化済みのaccessStopは共通IDの判定に使いません。別IDでも既存の同名500m以内の直接接続に該当する場合、サーバーが便の走査前に `walkingOnly:true, journeys:[]` を返します。500m超や禁止された別乗り場への接続は、この自動判定から除外します。

徒歩時間・距離・到着時刻は新しく作りません。カードの表示は「徒歩のみ」だけです。しおりでも共通ID、または既に取得済みの徒歩判定を使用して同じ表示にし、しおりを開くための追加検索は行いません。異なるIDの500m判定は、しおりを直接開いた時点で未取得なら、編集画面での判定取得後に反映されます。

保存済みの折り返し便のスナップショットは削除せず、徒歩区間の表示から除外します。その古い便の到着時刻を、次区間の候補絞り込みにも流用しません。徒歩の所要時間は未定なので、次区間に仮の徒歩到着時刻を設定しません。GTFS原本・有効版・停留所ID・観光地情報・保存済み旅程の一括変更はありません。

変更の中心: `transport_router.js`、`transport_journey_api.js`、`transport_journey.dart`、`itinerary_transport_options.dart`、`transport_journey_repository.dart`、`itinerary_editor.dart`、`itinerary_transport_sheet.dart`、`plan_screen.dart`、`itinerary_walk_test.dart` とサーバーテスト。

検証: 作業ツリーの `flutter analyze` 指摘なし、関連Flutter16件成功、サーバー38件成功、Firestore/Auth/Storageエミュレーター成功。共通ID・複数候補・別フィードID・500m境界・遠隔同名・禁止接続、折り返し便の早期抑止、所要時間を捏造しないこと、しおりと保存データ保持、検索回数0、古い折り返し便の到着時刻を次区間へ流用しないことを確認。

作業ツリー全体のテストでは、未コミットの別画面変更に関連する2件（チャットのCOMMUNITY見出し、空旅程の体験追加ボタン）が失敗しました。これらの画面変更とテストは変更・取消していません。公開用はHEAD `a6fe5bd` から今回の修正だけを `/tmp/tabisaki-walk-release` に分離し、全Flutter125件成功・6スキップ、静的解析指摘なし、WebビルドとFirebaseプラグイン登録ガード成功を確認しました。

検索Functionsと今回の修正のみを含むHostingを公開済みです。公開APIで共通停留所の `walkingOnly:true`、便候補なし、便走査0、到着時刻の未設定を確認しました。通常の札幌・夕鉄の直通/乗換候補と4回指定拒否も維持されています。公開前の分離ビルドをChromeで起動し、観光地・2フィード・Web SDKの圧縮候補17件を確認してから公開しました。
