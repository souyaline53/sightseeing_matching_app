# 交通データの登録・管理

2026年10月31日、依頼に基づき本番 `sightseeing-matching-prototype` の旧ダミー交通案内 `transit` 2件を削除し、新形式のサンプル3便を登録した。旧データ・変更前の観光地・交通マスターは `.local-backups/transport/2026-10-31T01-42-54.642Z.json` にバックアップ済み（Git対象外）。既存写真・説明・観光地IDは保持。旧交通の写真Storageパスは2件とも空で、画像削除は不要だった。

旧交通モデル・旧タブ・参考案内カード・旧Firestore購読を廃止。現在は新交通マスターのみ使用し、未登録区間は「未登録」と表示する。Firestore Rulesも旧transitの読み書きを禁止する内容に反映済み。旧案内から正式な便への自動変換はしていない。

## 登録済みの架空データ

すべて `sourceType: sample` / `verificationStatus: sample`。実際の運行情報としては使わない。

| 文書ID | 例 | 始発 → 終着 |
|---|---|---|
| `sample_trip_0` | 朝便 | 08:12 → 09:10 |
| `sample_trip_1` | 午前便 | 09:12 → 10:10 |
| `sample_trip_2` | 深夜便 | 25:10 → 26:10 |

関連データ：事業者 `sample_agency`、停留所 `sample_a`〜`sample_d`、路線 `sample_route`、運行日 `sample_service`、区間運賃 `sample_fare_b_c`（架空の大人300円）。途中停留所を含む4停留所の時刻表。

画面確認用として以下の観光地にサンプルアクセスを追記した。既存のアクセス情報を置き換えず、徒歩時間は `null` のままにした。

| 観光地ID | 架空停留所 |
|---|---|
| `melon` | `sample_b` |
| `lake` | `sample_c` |
| `rail` | `sample_d` |

この3スポットを上記の順に並べれば、途中停留所からの乗降・3便切り替え・運賃の表示を試せる。実際のスポット間の公共交通を表すものではない。

## 管理画面から追加する

1. メール確認済みの管理者でログインし、管理者メニュー → **交通時刻表**タブを開く（右上の時刻表アイコンからも開ける）。
2. 便一覧には上の3件が表示される。行を押すと編集、右端の **複製して追加** を押すと新IDで登録するフォームを開く。
3. 新しい便は別IDにする。複製時は元ID・作成日・更新日を除き、停留所・路線・運行日を引き継ぐ。名前・時刻・路線などの入力欄を変更して「この1件を保存」。元の便は変更しない。
4. 路線や停留所から新設する場合は、上部の選択欄で **①事業者 → ②駅・バス停 → ③路線 → ④運行日 → ⑤便 → ⑥運賃** の順に登録する。
5. 実データを登録する際は `sourceType` を `manual` 等に変更し、公式の `sourceUrl`、`sourceCheckedAt` と確認状態を記録する。サンプルを複製しただけで `verified` にしない。

一覧は先頭100件。JSONを記入する欄は廃止し、項目別の入力フォームと「交通データの追加手順」を画面内に用意している。大規模な一覧検索・入力補完・GTFS一括取込は未実装。

## コレクションと参照ID

| コレクション | 主なフィールド |
|---|---|
| `transport_agencies` | name, website, timezone |
| `transport_stops` | name, type, latitude/longitude, **routeIds**, agencyId, parentStationId, gtfsStopId |
| `transport_routes` | agencyId, name, mode, routeCode, sourceType, sourceUrl, verificationStatus |
| `transport_services` | timezone, validFrom, validTo, weekdays, addedDates, removedDates |
| `transport_trips` | **routeId, serviceId, stopTimes**, headsign, sourceType, sourceUrl, sourceCheckedAt, verificationStatus |
| `transport_fares` | routeId, fromStopId, toStopId, amountYen, fareType |

特に停留所の **routeIds** に、その停留所を通る路線の内部IDを列挙する。便のrouteId、serviceId、stopTimes内stopIdも対象文書のIDと一致させる。駅・駅前バス停・別の乗り場は必要に応じ別IDにする。

GTFSのgtfsAgencyId / gtfsStopId / gtfsRouteId / gtfsServiceId / gtfsTripIdも追加キーとして保持できる。停留所→routeIds→路線ごとの便/運賃を100件ずつ取得し、無関係な地域の全便は取得しない。停留所集合単位のRiverpodキャッシュは更新ボタンで破棄する。現在のクエリーは標準インデックスを使い、追加の複合インデックス設定は不要。

## 時刻・運行日・信頼性

- 時刻は運行日開始からの非負整数分。08:10=490、25:10=1510。到着と出発は別フィールド。null/省略は「—」。sequence順に扱い、pickupAllowed/dropoffAllowed=falseは乗降不可。
- servicesの日付はYYYY-MM-DD、weekdaysは月曜1〜日曜7。removedDates、addedDates、有効期間＋曜日の順に判定する。祝日は自動算出しないため例外日を登録する。日本向けにtimezoneはAsia/Tokyoで登録する。
- 状態はsample / verified / needsReview / unverified。確認済みも運行保証・接続保証ではない。旅行日未定でも参考時刻表を確認できる。
- 運賃は登録値のみ。現在はfareType=adultの区間運賃を表示する。未登録の運賃を推定しない。
- createdAt / updatedAt / sourceCheckedAtを記録する。新管理フォームの日時はUTC ISO文字列。Firestore Timestampも読み取り・バージョン比較できる。

## 観光地に最寄り停留所を設定する

管理者メニュー → 観光地情報 → 対象観光地を編集し、「最寄り駅・バス停を追加」から停留所・徒歩時間・徒歩距離・主なアクセス・情報源・確認状態を個別入力する。空欄の徒歩時間は不明として保存される。以下は内部保存形式の参考で、管理画面で記入する必要はない。

```json
[
  {
    "stopId": "stop_001",
    "walkingMinutes": null,
    "walkingDistanceMeters": null,
    "isPrimary": true,
    "sourceType": "manual",
    "verificationStatus": "unverified"
  }
]
```

stopIdは登録済み停留所IDに合わせる。徒歩時間は実際の入口までの根拠がある整数を記録し、不明ならnull。複数候補を設定できる。accessNotesやsourceUrl、sourceCheckedAtで入口・経路・根拠も記録する。accessStops未登録の観光地も利用可能。

## 旅程と保存

各区間の乗降停留所・選択便・徒歩時間・旅行日・便更新版をtransportSelections、滞在時間をstayMinutesに保存する。従来どおり端末内のSharedPreferences `tabisaki.trips.v1` を使い、既存旅程は読み込み可能。並べ替えでは便選択を解除して再選択を促す。日付変更や便更新は再確認を促す。しおりには選択時点の控えを表示する。

乗換経路探索・前スポットの滞在終了時刻を使った接続判定・リアルタイム運行・海外タイムゾーン変換・端末間同期は対象外。

## メンテナンスコマンド

通常の追加は管理画面で行う。以下は今回の置換作業のためのスクリプトで、既定では読み取りだけ。

```bash
node tool/replace_transport_samples.mjs
```

`--apply --spot-ids=melon,lake,rail` を付けると、バックアップ後、sample.jsonのマスター登録と該当スポットへのサンプルアクセス追記、旧transit全件削除を行う。**今後の通常追加には使わない**。サンプル以外の同名文書があれば中止。更新時刻の事前条件付きで変更を1回の原子的コミットにまとめ、途中まで削除された状態を防ぐ。サンプルアクセスは再実行しても重複しない。

ローカル検証：

```bash
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
  firebase emulators:exec --only auth,firestore,storage \
  --project sightseeing-matching-prototype \
  'node tool/check_cloud_emulators.mjs && node tool/check_transport_replacement.mjs'
```

この検証はローカル専用。削除・3便登録・既存フィールド保持・再実行・正式データとのID衝突拒否とアクセス権限を確認する。

## 入力形式と検証

- 名称・説明は文字列。整数欄（徒歩分数・距離・運賃・停車順・表示順等）は数字のみ入力でき、保存時にも整数型・範囲を検証する。
- 緯度・経度は符号付き小数と範囲を検証する。IDは英数字・ハイフン・アンダースコア（既存観光地IDには半角スペースも許容）。
- 日付はカレンダー、曜日は選択ボタン、交通手段・確認状態は選択欄、真偽値はスイッチを使う。URLもhttp/httpsを検証する。
- 時刻は08:10 / 25:10形式で入力し、保存時に整数分へ変換する。不明は空欄。分の範囲・発着順・停車順の重複も検証する。
- 停留所・路線・例外日・アクセス情報は行の追加・削除で設定する。参照先は登録済み候補（先頭100件）から選べる。候補取得に失敗してもIDを直接入力できる。
- 既存の追加メタデータは編集対象外でも保持し、保存に失敗しても入力内容を保持する。今回のフォーム改修で本番データの書き換えは行っていない。

## 旅程タブのカード・地図・シート

旅程タイトルと日付の下に写真カードを横並びで表示する。カード右上はドラッグハンドルで、タップすると前後への移動・滞在時間・削除の操作メニューを開く。色はアプリの深緑を使用する。

カードの下にはピン・経路線のないOpenStreetMapを表示し、その上に交通情報のBottomSheetを重ねる。カードを常に操作できるよう主シートは画面内に常設し、上下にドラッグできる。「地図で見る」でシートを下げ、固定された上部を上にスワイプすると展開する。指を離すと最小位置か最大位置の2段階に収まり、中間位置には止まらない。タッチ・マウスの両方に対応する。地図の取得に失敗しても編集・保存は継続できる。

便一覧は発着時刻・路線・運賃をコンパクトに表示する。便ごとの「時刻表・アクセスを見る」はモーダルシートを開き、徒歩・途中停留所の全時刻・情報源・確認状態を表示する。下部の「しおりに反映」で旅程を保存する。
