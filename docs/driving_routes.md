# 車での旅程

車の場合は公共交通の検索を実行せず、Callable `searchDrivingRoute` がGoogle Routes APIの `computeRoutes` (`DRIVE`, `TRAFFIC_UNAWARE`) を呼び、所要秒数と距離だけを返す。座標がない場合は施設名称と住所を渡す。Firebase匿名認証または登録済み認証が必要。

旅程作成画面としおりで全区間の車ルートを取得し、出発地は旅程の出発時刻（初期値8:00）、それ以降は前区間の到着＋滞在時間を初期出発時刻として自動保存する。保存ボタン・区間ごとの出発日選択は設けない。交通情報シートで出発時刻を変更すると即座に保存し、後続区間も再計算する。選択した時計時刻が前区間の到着＋滞在時間より早ければ翌日の時刻として扱う。車には到着28:00の上限を設けず、24時以降は「翌日0:00」、48時以降は「2日後0:00」の形式で表示する。所要秒数は分単位に切り上げ、渋滞・休憩を含まない目安として表示。日付・旅全体の出発時刻変更では初期時刻を再計算し、手動設定した区間も含めて新しい日程へ更新する。

旅行のしおりは車の出発・到着予定・所要時間・距離を表示。マップリンクはiOSならApple Maps、Android/WebならGoogle Mapsに両端の名称＋住所（未登録なら座標）と車移動を渡す。区間の出発・到着予定時刻を上部に大きく表示し、マップアプリへの誘導は大きいボタンで表示する。ルート未取得区間は取得後に自動保存する。車ではAI作成ボタンをグレー表示し、タップすると非対応のダイアログを表示。旧「どちらでも」(保存値2) は公共交通へ移行。

## 実環境への反映

1. 対象Google CloudプロジェクトでRoutes APIと課金を有効化し、Routes APIに制限したサーバー用APIキーを作成する。
2. `firebase functions:secrets:set GOOGLE_ROUTES_API_KEY` でSecret Managerに登録する。キーをFlutter・ソース・ログに含めない。
3. `firebase deploy --only functions:tabisaki:searchDrivingRoute,functions:tabisaki:optimizeTransportItinerary --project sightseeing-matching-prototype` でFunctionsを反映する。
4. Flutterアプリを反映して、実端末で車区間の保存・しおり表示・両端のマップ誘導を確認する。

API未設定・通信失敗時はエラーと再試行を表示し、公共交通や推定の架空時間へフォールバックしない。

仕様: https://developers.google.com/maps/documentation/routes/reference/rest/v2/TopLevel/computeRoutes
交通情報: https://developers.google.com/maps/documentation/routes/config_trade_offs

### 「No function matches given --only filters」が出る場合

このリポジトリは `firebase.json` で `codebase: "tabisaki"` を指定しているため、関数の指定は `functions:tabisaki:関数名` とする。リポジトリのルートで次を実行する。

```bash
firebase deploy --only "functions:tabisaki:searchDrivingRoute,functions:tabisaki:optimizeTransportItinerary" --project sightseeing-matching-prototype
```

このエラーはデプロイ対象の絞り込みによるもので、Routes APIキーの内容が原因ではない。

同じ住所（空白・全角数字・ハイフンの表記差は正規化）または同一座標にある地点間は、車APIを呼ばず「この区間は徒歩で移動できます」と表示する。しおりも徒歩扱いとし、車の移動時間を加算せず滞在時間を引き継ぐ。徒歩の所要時間は未計測のため表示しない。
