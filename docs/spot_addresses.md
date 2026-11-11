# 観光地の住所と座標

`sightseeing_spot` に `address`（文字列）、`latitude`（緯度）、`longitude`（経度）を保存する。
住所入力の700ms後に管理者専用のCallable Function `geocodeAddress` が国土地理院の住所検索を呼び出す。
候補が0件または複数件の場合、通信障害の場合はエラーを表示し、自動変換での保存を止める。
利用者は「緯度・経度を直接指定する」に切り替えて保存できる。住所はそのまま保持する。
住所検索の座標は代表地点となる場合があるため、番地の正確な位置を保証するものではない。

旅程の地図には旅程に含まれる観光地のピンを表示する。古い旅程に住所・座標がなくても、
同じIDの最新のカタログ情報を優先する。線やルート検索は追加しない。

## 本番データ移行

2026-11-11に `sightseeing-matching-prototype` の住所未設定の6件を更新・再取得で検証済み。
住所は `北海道夕張市高松7番地`、住所検索結果は緯度 `43.065662`、経度 `141.98732`。
バックアップは `.local-backups/addresses/2026-11-11T01-41-58.166Z.json` に保存した。
同じ住所なので、住所を個別に修正するまではピンが重なる。

移行スクリプトは住所未設定のレコードだけを対象にする。読み取りのみが既定値。

```sh
node tool/backfill_spot_addresses.mjs
node tool/backfill_spot_addresses.mjs --apply
```

更新前にバックアップを作成し、Firestoreの更新時刻による事前条件とフィールドマスクで他の変更を保護する。

## 本番反映

2026-11-11にユーザーの明示承認を受け、住所変換APIとFirestoreルールを本番反映済み。
ルールのコンパイルとリリース、関数の作成成功を確認した。
本番APIへの未認証リクエストがHTTP 403（PERMISSION_DENIED）になることも確認済み。
管理者アカウントからの実機での住所変換は未確認。

使用したコマンド：

```sh
firebase deploy --only functions:tabisaki:geocodeAddress,firestore:rules --project sightseeing-matching-prototype
```

アプリ側もユーザーの明示承認を受けて2026-11-11にFirebase Hostingへ公開済み。
`dart run tool/build_web.dart` の本番ビルドと `node tool/check_web_release.mjs --local-build` による
ブラウザー検証を通過後、`firebase deploy --only hosting --project sightseeing-matching-prototype` を実行した。
公開先: https://sightseeing-matching-prototype.web.app

公開後の `node tool/check_web_release.mjs` もPASS。新しいChromeで本番画面の起動、
観光地カタログ・交通データ・Storageの読み込みを確認済み。
