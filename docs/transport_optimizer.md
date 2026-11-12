# TABISAKI_Transport_Optimizer の実装準備

今回の到達点は、認証付きCallable `prepareTransportOptimization` から、独立したWorkflow用の `inputs.transport_json` を生成すること。既存マッチング、GTFS登録・管理、旅程画面・TripStateを変更しない。新しいProviderは明示呼出し専用で、既存画面から自動実行しない。本番照会・書込み・デプロイ・Dify通信は未実施。以下の保存構造は既存コードの調査結果であり、本番データの充足性を確認した結果ではない。

## 確認した既存保存構造

根拠: `functions/gtfs.js`, `transport_bundle.js`, `transport_import.js`, `transport_journey_api.js`, `manual_transport.js`, `lib/model/admin_transport_fields.dart`。

| GTFS | 登録後の実データ |
| --- | --- |
| agency | Storage `catalog.json.gz` の `agencies`: id, name, timezone 等。手動登録 `transport_agencies` |
| routes | 同カタログの `routes`: id, agencyId, routeType, name, routeFile。手動 `transport_routes` は routeType ではなく mode |
| stops | Storage `stops/{shard}.json.gz` および routing の stops: id, name, latitude/longitude, parentStationId, platformCode 等。手動 `transport_stops` |
| trips | 路線別 `routes/{hash}/trips-{page}.json.gz` の trips。手動 `transport_trips` |
| stop_times | trip内 `stopTimes`: stopId, sequence, arrivalSeconds/departureSeconds, arrivalMinutes/departureMinutes, pickupType/dropOffType 等。独立コレクションではない |
| calendar | servicesへ正規化: id, validFrom, validTo, weekdays（月曜1〜日曜7） |
| calendar_dates | services内 addedDates / removedDates（YYYY-MM-DD）。calendar無しの追加日だけのサービスも可。手動 `transport_services` |
| transfers | 検索用routingファイルのtransfers、手動 `transport_transfers`: fromStopId/toStopId, transferType, minTransferSeconds, from/toRouteId, from/toTripId |
| shapes | `shapes.txt` は原本保管のみ。既存パーサーは経路形状を正規化していない。今回も対象外 |

Firestore `transport_feeds/{feedId}` に activeVersionId と distribution（manifestPath/Checksum/Bytes、routing descriptor）。取込履歴は同ドキュメントの `versions` サブコレクション。Storage `transport_data/{feedId}/{versionId}/manifest.json` が圧縮ファイルのchecksum・容量を管理する。検索用は `routing-{checksum}.json.gz`。原本は `sourceDirectory` 参照。

既存routingDataは事業者・routeTypeを省くため、今回は既存loadNetworkのキャッシュを再利用したうえ、checksum検証付きのmanifest/catalogを追加取得する。手動の事業者・路線も補完。既存公開ファイル再生成・Firestore移行は不要。公開版とmanual revisionが同じwarmインスタンスでは再ダウンロードしない。各呼出で既存ローダーのフィードメタデータ・revisionを確認する。初回は手動マスター全体を200件ずつ取得（各種20,000件上限）するため、大規模運用には改善が必要。Firestore全GTFSレコードの繰返し読み取りはしない。

## 入出力とJSONサンプル

- 入力: `TransportOptimizationInput`、別々のorigin/destination、最大3 visits、旅行日・秒単位の制約・滞在、交通手段、優先条件、最低乗換余裕。
- 地点接続は既存AccessStopを使う。各visitのopeningは**指定旅行日について解決済み**の `known / closed / unknown` と秒単位windows。曜日・特別営業・休業日の自動解決は今回未実装。旧Experienceには営業時間が保持されないため、unknownが既定値。unknownを営業と断定しない。
- Callable応答: `{workflow: "TABISAKI_Transport_Optimizer", inputs: {transport_json: "JSON文字列"}, bytes: UTF8バイト数}`。
- 完全なデコード後サンプル: [transport_optimizer_sample.json](transport_optimizer_sample.json)。オフラインGTFS fixtureから生成し、実便の旅程として利用しない。再生成: `node tool/transport_optimizer_sample.cjs > docs/transport_optimizer_sample.json`。
- 出力モデル: `TransportOptimizationResult` は `status: feasible / infeasible / needs_review`, `candidates: [{id, ...}]`, `selectedCandidateId`。feasibleは選択IDの存在、infeasibleは空候補を検証する。candidate内部の訪問時刻・legs・参照便整合性の詳細検証は実Workflow契約確定後に追加する。このモデルだけを根拠に既存TripStateへ適用しない。

JSON中の`instances`は実運行日付き便ID、`segments`は隣接停留所の実乗車区間（秒、順序、乗降可否）、`transfers`は有向・便/路線条件付きルール。route/agency/stopsは必要IDだけ。各地点に徒歩接続と営業時間・滞在時間を格納する。訪問順は固定しない。

## 正しく扱う範囲とDify Codeノード側の契約

- Asia/Tokyoのみ。曜日・期間に追加/運休例外を適用（運休優先）。休日を自動生成せずcalendar_dates登録に従う。
- 時刻は旅行日の日本時間0時からの秒。前日以前の運行日・翌日以降も、便の時刻範囲から必要な運行日を列挙する。24時超を切り戻さない。出発から最大48時間。
- 指定時間窓内の全対象便の隣接区間を保持し、近隣停留所だけへの絞り込みは行わない。欠損時刻は補間せず区間を除外しwarningsへ。frequencyBasedとsampleは既存ローダーで除外するため、定時便の範囲での最適化となる。
- 同一instanceIdの連続sequence区間は乗り続けられる。途中停留所のdropoff不可でも継続乗車は可能。途中下車・新規乗車にはそれぞれdropoff/pickupを検証すること。欠落区間を飛び越えない。
- transfersは既存prepareNetworkによる親駅→プラットフォーム展開後のルール。便条件の優先度は両便→片便＋相手路線→片便→両路線→片路線→停留所。最上位の禁止を適用。type 3/4/5は今回禁止（4/5の車内継続拡張は未対応）。同一停留所でも別便には最低180秒以上のbuffer、明示値があればその最大値を要求。type 1でも時間余裕を省かない。
- 異なる停留所は明示接続・非負のminTransferSecondsが必要。自動同名500m接続は既存検索で使われるが、今回の確定経路には採用しない。transfer `usableForRouting: false` の正の接続は使用せず、禁止ルールは必ず評価する。
- 地点の徒歩接続は登録時間かつverificationStatus=verifiedかつsample以外のみ使用可。欠損時間は座標から直線距離/60m毎分を概算するがestimated=true、usableForRouting=false。時間だけ登録されたunverifiedも確定扱いしない。確認情報が足りなければ有効経路が出ない可能性がある。未知の徒歩を0分としない。
- walk未選択なら地点徒歩・停留所間徒歩を使わない。地点を直接停留所として扱う特例は未実装。
- Python側で最大3件の全順列（最大6）を評価し、営業時間内で滞在を完了し、最終到着期限を守る候補だけ作る。unknown営業時間がある候補はneeds_review。候補無しはinfeasible。LLMは計算済みcandidate IDの選択のみ担当する。

これらは計算入力の生成・保持の保証であり、今回Pythonによる経路探索・乗換可否・訪問可否の実計算は実装しない。

## データ量・不足情報と改善案

UTF8 JSONは500,000 bytesを暫定上限とし、超過はresource-exhaustedで実容量を返す。これはDifyの実環境の入力制限を保証する値ではない。手動構築時に入力変数の文字数/HTTPサイズ制限を確認し、バックエンド上限を合わせる。Dify入力変数は長文 `transport_json` を新設する。

全域の指定時間便を含むため、大規模フィードでは上限超過が想定される。候補を黙って切り捨てない。短い時間窓、あるいは乗換到達可能性を保つ部分グラフ索引（全訪問順序と出発/到着の接続を保持）を次段階で導入する。区間100,000件のメモリ保護上限もエラー。ネットワークローダー自体にも既存のフィード数/圧縮・展開容量上限がある。

路線種別が欠損・未対応、事業者が欠損、検索用routingが無い、非日本時間等は安全にfailed-precondition。拡張route_typeや船等は今回未対応。公開データ欠損のまま「最適」として返さない。運賃、バリアフリー、歩行道路、遅延、リアルタイム運休、shapes、frequencyサービスは未対応。

## 将来の独立Dify通信

今回のCallableはJSON生成だけで、実Dify API・鍵の読取を一切行わない。新Workflow作成後、別のFunctions Callableで同じ抽出処理を呼び、Secret Manager **DIFY_TRANSPORT_API_KEY** と独立したendpoint設定を使う。既存DIFY_API_KEY・matchingの入力変数に流用しない。既存ai_matching.jsの認証・UIDレート制限・タイムアウト・構造検証パターンを参照する。Secret値はFlutterへ返さない。Dify userは認証UIDのSHA-256、response_mode=blockingとし、outputs.transport_resultを検証する設計。endpoint・Secret設定、実通信・レート制限・詳細出力検証はその段階で実装する。

## 作成・変更ファイル

- functions/transport_optimizer.js: 純粋な入力検証・運行日抽出・正規化・容量判定。
- functions/transport_optimizer_api.js: 認証、既存ローダー再利用、カタログ補完。
- functions/index.js: 独立Callableのexportだけ追加。
- lib/model/transport_optimization.dart: 入力・生成結果・将来出力モデル。
- lib/service/transport/transport_optimizer_service.dart: 注入可能なモック対応通信Provider。
- functions/transport_optimizer.test.js、test/transport_optimization_test.dart: モック検証。
- tool/transport_optimizer_sample.cjs、本書、transport_optimizer_sample.json。

## 検証

- 新規Nodeテスト7件成功（運行例外、前日・翌日便、秒、途中停留所、便継続、徒歩、transferルール保持、上限、認証、Storage/Firestoreモックとキャッシュ）。
- 既存GTFS/バンドル/交通検索/近接停留所テスト42件成功。
- Flutter新規2件＋既存交通旅程/時刻表5件、計7件成功。
- 新規Dartファイル3点のflutter analyze: 指摘なし。
- 実Firestore・Dify疎通、デプロイ、既存UIへの適用は未実施。
