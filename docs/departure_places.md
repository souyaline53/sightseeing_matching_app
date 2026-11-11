# 管理者が登録する出発地

`departure_places/{id}` に登録する。IDを出発地の表示名・選択値として使用する。
例：`札幌駅`。作成後のID変更は不可。FirestoreドキュメントIDがIDなので、フィールドには重複保存しない。

保存フィールドは `address`（文字列）、`latitude` / `longitude`（数値）、
`accessStops`（観光地と同じ最寄り停留所の配列）、`createdAt` / `updatedAt`（タイムスタンプ）。
住所変換・エラー・座標の直接指定は観光地と同じフォーム・`geocodeAddress` を使用する。
最寄り停留所は `AdminFieldsForm` の `accessStopsField` を共有する。
出発地に紹介文・写真は登録しない。

## 読み取りと旅程

検索条件の選択ボタン、出発地選択地図、プロフィールの候補、旅程地図は
`departurePlacesProvider` からFirestoreの登録済み出発地を読み取る。
検索候補は登録件数に応じて増減し、読み込み失敗は検索画面でエラーと再試行を表示する。
登録済みでない出発地は検索画面の確定ボタンで先に進めない。

旅程の出発・帰着区間は出発地の `accessStops` を使う。
`isActive: false` は除外し、登録した徒歩時間・距離・確認状態を引き継ぐ。
札幌駅だけの停留所名の特例や、交通停留所側の `departurePlaceId` による探索は廃止した。
旧 `departurePlaceId` のメタデータは既存停留所に残るが、新しい検索では使用しない。
既存の旅程・プロフィールの出発地名は変更しない。

## 初期データ

2026-11-11に `functions/seed_departures.cjs --apply` で本番に4件を保存・再取得確認済み。
既存の出発地は上書きしない。保存前のバックアップは
`.local-backups/departures/2026-11-11T04-14-49.141Z.json`。

| ID | 住所 | 最寄り停留所数 |
| --- | --- | ---: |
| 札幌駅 | 北海道札幌市北区北6条西4丁目1番1号 | 12 |
| 新千歳空港 | 北海道千歳市美々987番地22 | 4 |
| 旭川駅 | 北海道旭川市宮下通8丁目3番1号 | 0 |
| 小樽駅 | 北海道小樽市稲穂2丁目22番15号 | 14 |

住所を国土地理院の検索で変換した座標を保存した。座標は住所の代表地点の場合がある。
最寄り停留所は本番の取り込み済みGTFS・手動停留所から対応する既存IDを登録し、
徒歩時間と距離は未確認なので `null` とした。架空の停留所は追加していない。
旭川駅に対応する交通データは現在未取り込みのため、最寄り停留所は空欄。
停留所追加後に管理画面から設定できる。

住所確認資料：
- [札幌駅（駅施設事例）](https://www-s.jp.toto.com/com-et/jirei/uploadfile/docs/2611.pdf)
- [新千歳空港](https://www.hokkaido-airports.com/ja/new-chitose/info/assets/docs/hokkaido-airports.pdf)
- [旭川市の旭川駅案内](https://www.city.asahikawa.hokkaido.jp/facility00/facility03/d61092.html)
- [小樽観光協会の小樽駅案内](https://otaru.gr.jp/shop/jr-otaru-station)

## 検証

管理画面からの日本語ID・住所変換・保存、出発地モデルの入力検証、
登録した最寄り停留所の参照と無効行の除外、既存検索・旅程画面の関連テストを実施。
Auth / Firestore / Storageエミュレーターで出発地の公開読み取り・管理者限定の作成と編集、
不正座標・想定外フィールドの拒否、既存カタログ等のルールを検証済み。

全体VMテストの結果は127件成功・6件スキップ・2件失敗。
失敗はチャット画面の旧見出し `COMMUNITY` を期待する既存テストと、
空の旅程で体験追加ボタンのタップ位置が画面外になる既存テスト。
出発地・管理画面・旅程の関連31件は成功している。

登録候補を1件だけに置き換える画面テストも成功（固定4択に依存しないことと、
未登録の初期値を確定できないことを検証）。本番用Webビルドとプラグイン検査は成功。

## 本番反映

2026-11-11にユーザーの明示承認を受け、Firestoreルールのみ本番反映済み。
ルールのコンパイルとリリース成功、および認証なしのFirestore REST APIによる
出発地4件の公開読み取り（HTTP 200）を確認した。

```sh
firebase deploy --only firestore:rules --project sightseeing-matching-prototype
```

ユーザーの指定によりWebアプリのデプロイはユーザーが実施する。
今回の出発地管理を含むアプリはまだ公開していない。
本番用 `build/web` のビルド・プラグイン検査・隔離Chromeでのホーム起動確認は成功済み。
必要に応じて再ビルドしてから公開する。

```sh
dart run tool/build_web.dart
node tool/check_web_release.mjs --local-build
firebase deploy --only hosting --project sightseeing-matching-prototype
node tool/check_web_release.mjs
```

公開後に検索画面での出発地候補表示も確認する。
