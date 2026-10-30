# チャット・自治体ユーザ

## 動作

- タブ順は「ホーム／旅を組み立てる／投稿／チャット／プロフィール」。既存タブの相対的な順序と起動時のホーム表示は維持します。
- チャットのヘッダーは `COMMUNITY` と「チャット」。丸いアバター、表示名、自治体／旅行者バッジ、最新メッセージ1行を表示します。画像を追加取得しないアイコン型アバターです。
- ログイン・プロフィール登録後、右下のボタンから表示名で相手を探し、1対1の会話を開始できます。会話・メッセージはFirestoreに保存し、双方の画面にリアルタイムで反映します。同じ組み合わせの会話は再利用します。
- メッセージはテキストのみ、1件2000文字以内、直近100件を表示します。送信失敗時は入力を保持します。画像・既読・通知・グループ・会話削除・それ以前の履歴の追加取得は今回の対象外です。
- サンプルアカウントや架空の会話は生成しません。ゲストも既存の旅行機能は利用でき、チャットタブからログインへ進めます。

## 属性とデータ

| 保存先 | 内容・権限 |
| --- | --- |
| `users/{uid}.userType` | `general`（初期値）または `municipality`。私的プロフィールは本人だけが閲覧できます。 |
| `public_profiles/{uid}` | `uid`、`displayName`、`userType`、`updatedAt` のみ。登録済みユーザーのチャット相手選択用です。メール・年代・住所は含みません。 |
| `chat_rooms/{roomId}` | 参加UID2件、最新本文・送信者・メッセージID、作成／更新日時。参加者だけが閲覧できます。 |
| `chat_rooms/{roomId}/messages/{messageId}` | 送信者UID・本文・サーバー作成日時。参加者だけが閲覧・送信できます。 |

属性未登録の旧プロフィールは一般ユーザとして扱います。再ログイン、またはチャットタブを初めて開いたときに、本人のプロフィールから公開用データを同期します。まだ新バージョンでログインしていない旧ユーザーは、相手選択に表示されない場合があります。管理者が自治体属性を設定したユーザーの公開情報はその時点で作成します。

通常のプロフィール編集ではFirestore上の既存属性を保持します。一般ユーザーが自分を自治体に変更したり、公開用バッジだけを偽装したりする書き込みはルールで拒否します。参加者・送信者の偽装、会話外からの取得、送信済み本文の改変も拒否します。最新メッセージと本文は同一バッチで保存します。

## 自治体ユーザへの変更

プロフィール→管理者メニュー→「ユーザー属性」で、対象者の登録メールアドレスを入力し、「自治体ユーザに変更する」を押します。

Callable Function `setMunicipalityUser`（`asia-northeast1`）がFirebase Admin SDKでメールからUIDを解決し、私的／公開プロフィールの属性を一括更新します。登録者全員のメールアドレス一覧をクライアントに公開する必要はありません。既存アカウントも対象にできます。

メール確認済みの `nichi-ka@nichi-ka.com` だけが実行できます。プロフィール未登録・未登録メール・無効なアカウントは変更しません。対象者のニックネームや年代・住所・作成日時は保持します。属性選択を一般ユーザーの登録／編集画面に追加していません。

## Firebaseへ反映

本改修では本番へのデプロイを行っていません。新しいルールとFunctionの反映が必要です。

```sh
cd /Users/souya/StudioProjects/sightseeing_matching_app
flutter pub get
npm ci --prefix functions
firebase deploy --only firestore:rules,functions:tabisaki --project sightseeing-matching-prototype
```

Cloud Functions用のBlazeプランと、関数をデプロイできるGoogleアカウント権限が必要です。関数のランタイムはNode.js 22です。管理者のTABISAKIアカウントのログインとは別に、Firebase CLI側でも対象プロジェクトへログインしてください。`gcloud` のローカルインストールは不要です。既存のStorage／CORS設定を変更する操作は含みません。

Firestoreのコレクションは保存時に自動作成され、今回のクエリでは追加の複合インデックスを要求しません。管理者によるメール検索は、デプロイ後のFunctionが実行します。Webアプリだけを更新してもこの処理は利用できません。

## ローカル検証

```sh
firebase emulators:start --only auth,firestore,storage,functions --project sightseeing-matching-prototype
```

別のターミナルから実行します。ユーザーやメッセージを作成するのはローカルのエミュレーターのみです。

```sh
npm test --prefix functions
node tool/check_chat_emulators.mjs
flutter test test/chat_test.dart
flutter test --platform chrome --dart-define=AUTH_EMULATORS_TEST=true --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 test/chat_browser_test.dart
flutter run -d chrome --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1
```

Functionsは5001、Authは9099、Firestoreは8080、Storageは9199を使用します。エミュレーターのJavaは21以上、関数開発用Node.jsは22を推奨します。
