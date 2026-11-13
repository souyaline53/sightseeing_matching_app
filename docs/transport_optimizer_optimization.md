# 交通ネットワーク生成・読取コストの最適化報告

既存schemaVersion: 1を維持し、重複読取解消・抽出結果キャッシュ・サイズ計測を実装した。**2026-11-13、実行ログで約24MBの容量超過を確認したため、接続・時刻・必須訪問を考慮した軽量化を既定で有効化した。** 最新のオフライン比較は [検証結果](transport_preparation_default_pruning_verification.json) と [UI統合報告](ai_trip_creation.md) を参照。以下の初回比較表は以前のアルゴリズムの測定値。実Dify出力一致・実送信時間は引き続き未検証。

Firestore・Storageの読取り専用実測以外の本番操作、デプロイ、Workflow変更、APIキーの取得、Dify課金呼出しは行っていない。

## 調査結果と変更箇所

- GTFSの取込データはFirestoreの全件コレクションではなく、`transport_feeds/{id}` のactiveVersionId/distributionとStorageの不変圧縮ファイルに保存される。
- trips/stop_timesはroutingファイル内のtrips/times、stops/routes/services/transfersも同ファイル。事業者・routeTypeはcatalogから補完。calendar/calendar_datesはservicesのweekdays/validFrom/validTo/addedDates/removedDates。既存のoperates判定を変更せず再利用する。
- 手動データは `transport_stops/routes/services/trips/transfers/agencies`。`allRows`で__name__順・200件ページ、各種20,000件上限。これは初回・manual revision更新時に読む。GTFSを日付クエリでFirestoreに取りに行く構造ではないため、新しい日付索引は追加していない。
- `firestore.indexes.json`の複合索引は空。stopTimes、fare rules、service追加/運休日、pattern stopIdsには既存の索引除外設定がある。変更していない。配列内のstop_timesへ時間クエリを追加する案はこの構造に適合しない。
- 既存のネットワークキャッシュはフィード公開版/checksum＋manual revisionで更新する。従来交通検索には独立の結果キャッシュもある。既存の検索アルゴリズムと返却結果を変更していない。

| ファイル | 今回の変更 |
| --- | --- |
| functions/transport_journey_api.js | 取得済みactiveFeedsとmanualRecordsをサーバー内部のキャッシュ結果へ追加。既存検索の処理・クエリは維持 |
| functions/transport_optimizer_api.js | 重複フィード取得・手動路線再取得を解消、共通データキャッシュ、サイズ・読取メトリクス、区間除去の設定フラグ |
| functions/transport_optimizer.js | 地点正規化をnormalizePlacesへ抽出。同じ入力に同じ地点データを返す |
| functions/transport_payload_optimizer.js | 重複検証、接続成分・時間到達性、LRU/TTL、コンパクトJSON計測・容量エラー |
| functions/transport_read_metrics.js | SDK成功readのクエリ数・単体get数・返却ドキュメント・空クエリ計測 |
| functions/transport_optimizer.test.js | Callable・キャッシュ間のユーザー入力分離を追加検証 |
| functions/transport_payload_optimizer.test.js | 重複・矛盾・接続・遠回り・同時刻・Unicode・上限・キャッシュ・read計測、7件 |
| functions/test_support/transport_payload_reference.js | 既存ローカルrouterを比較用に使用するv1アダプター。Dify代替実装として運用しない |
| tool/compare_transport_payloads.cjs | 7条件のサイズ・ローカル経路比較と比較JSON生成 |
| tool/measure_transport_preparation.cjs | before/afterを別プロセスで本番read計測。baselineはgit HEADの変更前API |
| docs/transport_optimizer_*_optimized.json | 区間除去を適用したレビュー用サンプル。既存の入力サンプルを置換していない |
| docs/transport_optimizer_payload_comparison.json、transport_optimizer_reads_before/after.json | 実測結果 |

作業開始前から存在していた未コミットのサンプルJSON・スクリプト・ドキュメントを保持している。Flutter、既存マッチング、GTFS取込・管理画面、旅程画面、Firestore Rules・索引・既存データへの変更はない。

## Firestore読取：実測

`node tool/measure_transport_preparation.cjs --before` と `node tool/measure_transport_preparation.cjs` を別プロセスで実行。それぞれ初回coldと2回目warmを計測した。対象の公開ネットワークはどちらも4,230停留所・9,105便で一致する。

| 指標 | cold前 | cold後 | warm前 | warm後 |
| --- | ---: | ---: | ---: | ---: |
| query.get回数 | 9 | 7 | 1 | 1 |
| 単体doc.get回数 | 1 | 1 | 1 | 1 |
| SDK呼出し合計 | 10 | 8 | 2 | 2 |
| 返却ドキュメント数 | 9 | 6 | 4 | 4 |
| うち空クエリ数 | 6 | 5 | 0 | 0 |
| ネットワーク取得時間ms（単発） | 9,810 | 8,228 | 251 | 770 |

coldはフィード3件の重複readと空の手動路線クエリ1回を解消。手動事業者はroutingファイルにないため初回に取得する。warmは既に公開フィード3件＋manual revision1件の確認のみで、ここをTTLに置換して読取りを減らすと更新の検知が遅れるため維持した。単発時間はネットワーク変動を含み、warmが高速化したとは言えない。

これは**成功したSDK readで返されたドキュメント数**の実測であり、課金エクスポートの読取数ではない。空クエリにも最低1読取の課金があるため、返却数だけで料金を算出しない。[Firebase公式料金説明](https://firebase.google.com/docs/firestore/pricing)。SDK内部リトライ・索引エントリread・Storage転送費用は今回のメトリクスでは未計測。

## キャッシュ方式と更新

追加キャッシュはFunctionsインスタンス内のLRU、最大16MiB、TTL5分。Firestoreキャッシュドキュメントは作らず、追加の書込み費用は発生させない。TTL内でも各要求の公開版/manual revisionを既存ローダーで確認し、異なる版ではキーが変わる。キャッシュはインスタンス間共有ではなく、cold startでは作り直す。

キーは内部schema、ネットワーク公開版/checksum/manual revision、旅行日、時間窓、交通手段、最低乗換余裕、origin/visits/destinationの全access stop IDとその順序、区間除去フラグをSHA-256化する。事業者・路線・対象範囲は現在の全公開版集合とaccess接続成分によって識別する。将来明示的な路線/事業者フィルターを追加する場合は、その設定もキーへ追加する必要がある。

キャッシュには交通データとサイズの数値を保持し、地点名・ユーザー座標・営業時間・滞在時間・優先条件は保持しない。placesとpreferenceは毎回現在の入力から組み立て直す。現在の区間除去は歩行時間・営業・滞在時間を**緩和して無視**するため、これらが変わっても共通部分は安全な上位集合のままになる。返却JSONの前後サイズはキャッシュhit時も現在の地点・優先条件へ補正して測る。返却オブジェクトを変更してもキャッシュを汚染しない。

## 日付・時刻・接続に基づく抽出

従来の運行日判定と秒単位の時間窓抽出を維持した。始発時刻だけで便を除外せず、途中停留所の各隣接区間を確認する。前日の25時台・翌日便も運行日offsetで旅行日0時からの秒へ変換する。欠損時刻の補間や架空便の追加はしない。

2026-11-13から区間除去は既定で有効。`TRANSPORT_OPTIMIZER_PRUNE=false` を明示すると診断用に無効化できる。今回も本番デプロイ・環境変数変更は実行していない。

1. 全便の接続と全登録transferを**無向接続**として、入力地点のaccess stopを含む連結成分を取得する。矩形や距離による削除はしない。禁止transferも接続として扱うため、必要以上に残す側へ緩和する。別地域を通る遠回りも同一接続成分なら残る。
2. 既存抽出で実運行日・実時間窓のsegmentsを作る。
3. originからの最早到達・destinationからの最遅到達を固定点まで計算する。transfer時間、禁止、便/路線条件、pickup/dropoff、地点徒歩、営業、滞在を緩和し、同一地点のaccess stops同士も0秒として扱う。この緩いネットワークでさえ乗れない区間のみ除く。同時刻・0秒区間は入力順によらず固定点反復で保持する。
4. 元segmentsの順序・値・IDを維持し、区間が全て消えたinstancesだけ除く。stops/routes/agencies/transfers/warningsは診断・表示利用が未確認のため残す。未対応transferも削除しない。残存区間は結合・短縮・時刻変更しない。

この除去が安全という説明は、経路探索が**入力に存在する区間・明示transfer・地点access接続だけを使う**場合に限る。Code ②が座標から新しい歩行辺を生成したり、入力全件の走査数で候補を打ち切ったり、除外した便を独自ルールに使ったりする場合は実コードとの比較が必要。既存ローカルrouterの同名500m自動歩行も今回の比較では明示的に無効化している。2026-11-13の修正では、入力契約（allowEstimatedWalking=false、明示接続）に従う経路を保持する訪問状態付きの処理を既定で有効にした。Dify独自実装の実出力一致については未検証のままである。

## JSONの前後実測

以下は**区間除去を明示的に適用した比較用サンプル**。初期実装時点の本番経路は完全重複除去のみだった。この表は当時の比較であり、2026-11-13以降の訪問状態付き軽量化の削減率とは別。

| 指標 | メロード前 | メロード後 | メロード＋博物館前 | メロード＋博物館後 |
| --- | ---: | ---: | ---: | ---: |
| Unicode文字数 | 293,549 | 176,265 | 460,989 | 350,585 |
| UTF-8 bytes | 295,001 | 177,717 | 462,533 | 352,129 |
| instances | 103 | 78 | 192 | 170 |
| stops | 141 | 141 | 99 | 99 |
| segments | 920 | 505 | 1,463 | 1,071 |
| transfers | 2 | 2 | 2 | 2 |
| bytes削減率 | — | 39.76% | — | 23.87% |

[メロード軽量化候補](transport_optimizer_meroad_optimized.json)、[2観光地軽量化候補](transport_optimizer_meroad_coal_optimized.json)。両方ともv1 JSONであり、文字数40万未満。元のサンプルファイルは変更していない。

ID短縮、metadataの削除、null除去、配列形式への変換、gzip/base64化は行っていない。未使用フィールドはCode ②/③だけでなく後段LLM・Code ④・表示・監査にも使われ得るため、実際のWorkflowが無い状態で削除しない。反対に同じIDで値が矛盾するレコードはdata-lossとして停止し、上書きで隠さない。

## サイズ制限

- 最終送信文字列に改行・空白なしのJSON.stringifyを使う。
- Unicode code point数、UTF-16 units、UTF-8 bytesを毎回測る。
- `DIFY_TRANSPORT_MAX_CHARACTERS`（既定4,000,000）、`DIFY_TRANSPORT_MAX_BYTES`（既定4,000,000）。2026-11-12に送信上限を引き上げ。Dify Codeノードの出力上限400,000文字とは別に検査し、入力のいずれかの上限を超えればresource-exhausted。UTF-16でも同じ上限を適用する保守的な判定。エラーdetailsと集計ログに実サイズを残す。途中切捨てなし。
- 既存の抽出メモリ上限・便/区間数上限は維持する。中間JSONは最終軽量化前に500KBを超え得るため、内部生成の検査上限は32MiBとする。最終送信では上記の文字数・バイト数の上限を別途検査する。
- [Dify公式ソース](https://github.com/langgenius/dify/blob/main/api/configs/feature/__init__.py)にはCODE_MAX_STRING_LENGTHの既定400,000がある。ただしこれはCode出力の設定であり、開始ノードtransport_jsonの入力上限とは別。使用中のDifyの実設定・バージョンは接続情報が無いため未確認。開始ノードの上限が低ければFunctionsの環境変数もその値以下に設定する。今回の値を実環境確認済みとは扱わない。

## 経路比較と限界

既存ローカルtransport_routerを、明示接続だけを使うv1アダプター経由で比較した。各訪問順序、経路の便・乗降停留所、出発/到着時刻、滞在時刻、乗換回数、徒歩秒、requiresReview相当、warningsについてdeepEqualで比較した。比較結果は[全件JSON](transport_optimizer_payload_comparison.json)。

| ケース | ローカル前後一致 | 比較で得られた候補数 |
| --- | --- | ---: |
| 札幌→メロード→札幌 | 一致 | 1 |
| メロード→博物館 | 一致 | 1 |
| 博物館→メロード | 一致 | 0 |
| JR・バス乗換 | 一致 | 1 |
| 日跨ぎ | 一致 | 1 |
| 営業時間に間に合わない | 一致 | 0 |
| 利用便なし | 一致 | 0 |

日跨ぎの比較ケースは登録サンプル全体を10時間シフトした**合成テスト**であり、実際の運行日・便を変更して公表したものではない。別途既存GTFSテストで前日運行日の24時超・運行例外を検証した。全順列をまとめて選ぶDify処理は実行せず、両方の順序をそれぞれ比較した。

候補1件は他の候補が存在しない証拠ではない。候補0件も、ここで使ったローカルアルゴリズムの範囲の結果であり、Difyや全交通網で不可能であることを意味しない。とくに博物館→メロードはローカルrouterの段階的な最早到着探索と比較時間窓の制約を引き継いでいる。今回これを理由に逆順を入力から削除したり、順序を固定したりしていない。

Dify Code ②/③を取得できていないため、**Difyの実候補一覧・ランキング・requiresReview理由の一致は未検証**。API実送信時間は未計測で、JSONにはdifySendMs=nullと記録している。生成時間・ネットワーク取得時間を送信時間へ流用していない。

## 残作業

1. Code ②/③（可能ならWorkflow DSL全体）と開始ノード入力長を取得し、使う全フィールド・接続生成・候補打切り条件を確認する。
2. 同じ7条件を実際のPythonコードで比較し、訪問順序・候補一覧・時刻・review/警告が一致した場合に限り区間除去フラグを有効化する。
3. 50%以上の削減には、消費されないmetadataの確認後削除、もしくは訪問必須条件を含むより強い到達性判定を検証する。現在のコードを見ずに必須フィールドを削ったりIDを短縮して目標だけを満たさない。
4. Dify送信が実装されている実運用側の呼出し箇所を特定し、同じserialize/計測を送信直前へ適用する。このリポジトリの交通Callableは依然としてJSON準備のみ。既存マッチングのDify通信は対象外。
5. より大規模なデータでは運行日/時間索引付きStorage bundleを検討できるが、取込形式・公開版の移行が必要なので今回実施しない。Firestoreへ大量レコードやキャッシュを書き足す案も実施していない。

検証: Nodeの関連60テスト成功、7ケースの比較スクリプト成功、git diff --check成功。新規/変更JSはnode --checkで確認する。Flutterコードは変更していない。
