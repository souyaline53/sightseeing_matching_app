# 観光地の訪問情報

対象は `sightseeing_spot`。AI推薦API、Dify、交通情報、カードの見た目は変更していません。本番書き込み、移行、デプロイは実施していません。

## 変更ファイル

- `lib/model/spot_visit_info.dart`：追加データ、初期値、選択肢定数、検証、営業判定、再帰Mapマージ。
- `lib/model/catalog_record.dart`：既存レコードに `visitInfo` アクセサを追加。
- `lib/screen/admin/spot_visit_info_form.dart`：既存の共通入力Widgetを利用する編集セクションと編集用ドラフト。
- `lib/screen/admin/catalog_edit_screen.dart`：観光地だけに追加フォームを表示し、検証後に保存。
- `lib/service/cloud/catalog_admin_service.dart`：画像アップロード前にも追加項目を検証。
- `lib/repository/firestore_catalog_repository.dart`：現在のドキュメントと再帰マージし、追加項目の初期値・型を整えてトランザクション保存。
- `firestore.rules`：追加フィールドを許可し、状態・基本型・料金等を検証。既存の管理者認証条件は維持。
- `test/spot_visit_info_test.dart`：互換性、検証、営業判定、カード変換、フォーム操作のテスト。
- `tool/check_spot_visit_emulators.mjs`：ローカル専用の保存・再読込・ルール検証。
- 本ファイル。

## Firestoreフィールド

| フィールド | 未登録時 |
| --- | --- |
| openingHoursStatus | unknown |
| openingHours | null |
| specialHours | [] |
| seasonalAvailability | {status: unknown, periods: []} |
| recommendedSeasons | [] |
| environmentType | unknown |
| admissionFee | {status: unknown, adultYen: null, childYen: null, note: ""} |
| reservationRequired | null |
| experienceTags | [] |
| officialUrl | 空文字列 |

既存のフィールド名と型を維持。読み込みだけではFirestoreへ初期値を書き込みません。編集保存時に追加項目を保存します。省略された既存項目・Map内の独自情報は保持し、配列は編集後の内容に置き換えます。`createdAt` は保持、`updatedAt` は既存どおりサーバー時刻です。

管理画面には「営業時間・営業期間」「施設情報」「体験情報」の折りたたみセクションを追加しました。曜日ごとの営業スイッチ、複数時間帯、特別営業日、複数季節期間、季節・体験タグの複数選択、予約の3択等を利用できます。料金の空欄はnullで、無料とは区別します。

時刻は `HH:mm`、開始は00:00〜23:59、終了のみ24:00も利用できます。逆転・同時刻・重複・日付をまたぐ時間帯は拒否します。特別営業日は実在するYYYY-MM-DDで重複不可。臨時休業の時間帯は空配列、特別営業には時間帯が必須です。季節期間は年をまたげます。月日の妥当性は閏年で確認し、2月29日を許容します。

## 営業判定と次回の統合

`CatalogRecord.visitInfo` または `SpotVisitInfo.fromMap(document)` で取得し、`validate()` で検証、`toMap()` でFirestore形式を得られます。

`evaluateSpotVisit(info, arrival, durationMinutes: record.data['minutes'])` は副作用のない関数です。arrivalはタイムゾーンを持つ訪問予定時刻（UTC推奨）を渡してください。日本時間で評価し、`SpotVisitStatus.open / closed / unknown` を返します。

判定順は季節期間 → 特別営業日 → 通常の営業時間です。季節期間外の施設は特別営業日があってもclosedとします。祝日の自動補正はしません。未登録の営業時間はunknownです。常時利用可能でも特別休業日はclosedとなります。所要時間と閉館時刻、滞在中に日付が変わる場合の翌日の設定も確認します。

既存のAI APIには組み込んでいません。次回Functionsで絞り込む際は、このDart関数の仕様・テストに合わせたサーバー側実装を用意してください。Firestoreルールは管理者権限と基本型を検証し、時間帯の重複や期間の詳細検証はモデルと保存サービスが担当します。

## 検証結果

- `flutter test test/spot_visit_info_test.dart test/admin_forms_test.dart test/cloud_catalog_test.dart test/catalog_test.dart`：32件成功。
- `node tool/check_spot_visit_emulators.mjs`：成功。demo-tabisaki-visitのAuth/Firestore Emulatorだけを使用。全新フィールドの再読込、旧形式、createdAt維持、管理者権限、不正な状態・型・負料金・HTTP URLの拒否を確認。
- `flutter analyze`：既存ファイルに14件（warning 5件、info 9件）。今回の変更ファイルには指摘なし。
- 追加で実行した `test/add_experience_test.dart` は3件中2件成功、1件失敗。`add button also opens cards after restart with no question answers or saved trip` でボタンのタップが命中せず、`showCoal` が `Bad state: No element`。今回の変更範囲外として未修正。

エミュレーターの再実行例（JavaがPATHに必要）：

```sh
firebase emulators:start --only auth,firestore,storage --project demo-tabisaki-visit
node tool/check_spot_visit_emulators.mjs
```

残課題は既存の解析指摘と上記の旅程テスト失敗の調査です。AI統合・一般カードへの新情報表示・祝日の繰り返し規則・深夜営業は今回の対象外です。更新したFirestoreルールのデプロイも実施していません。
