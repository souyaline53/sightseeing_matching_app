# JR北海道GTFSの登録記録

- 登録日: 2026-11-11（日本時間）
- Firebase project: `sightseeing-matching-prototype`
- Feed ID: `jr_hokkaido`
- Version: `7a131426301ee21c23e9114094f94dcdb0875e536ff82ab3cfb40df9b3b9d610`
- 7路線、77駅、413便、4,264停車時刻
- 運行期間: 2026-10-23〜2027-02-28
- 運賃データなし。画面では「運賃未確認」と表示。
- `train_types.csv` の `limited_express` は有料特急。他の種別は有料特急として扱わない。
- 有料特急候補がある区間でのみ「有料特急を使う」スイッチを表示（初期値オフ）。乗換経路の一部が有料特急の場合も対象。
- 検索では特急を含む候補に加え、特急を除外した検索結果も保持する。

原本8ファイルは `transport_imports/maintenance/jr_hokkaido/7a131426301ee21c23e9114094f94dcdb0875e536ff82ab3cfb40df9b3b9d610/` に保存。補足の `source_provenance.csv` と `missing_station_coordinates.csv` も同じ場所に保存・照合済み。
配信94オブジェクトの再ダウンロードとハッシュ照合、Firestoreの有効バージョンとマニフェストの照合を実施して公開。
確認後に `assets/jr_all_combined_with_train_types/` を削除した。

再登録する場合は原本を復元し、リポジトリルートで `node functions/stage_transport_feeds.cjs --jr-hokkaido --apply --activate` を実行する。
