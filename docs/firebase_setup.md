# TABISAKI：任意登録とFirebaseの設定

## 今回の接続先

既存プロジェクト `sightseeing-matching-prototype` にWeb・Android・iOSアプリを登録し、FlutterFire CLIで接続設定を生成しています。

- Web：`lib/firebase_options.dart`
- Android：上記Dart設定と `android/app/google-services.json`、Google Services Gradleプラグイン
- iOS：上記Dart設定と `ios/Runner/GoogleService-Info.plist`（Runnerのリソースに追加済み）

これらはクライアント用設定です。サービスアカウントの秘密鍵は使用しません。iOSの最低対応バージョンは今回のFirebase SDKに合わせて15.0に設定しています。Androidは現在のFlutter既定値のAPI 24です。実機ビルドは未確認です。[FlutterFire公式セットアップ](https://firebase.google.com/docs/flutter/setup)

アプリ接続設定とは別に、認証方式・データベース・ルールの設定が必要です。観光地クラウド対応時にFirestore `(default)` の作成済みを確認しました。ルールの本番反映は今回実行していません。以下と [クラウド移行ガイド](cloud_catalog_setup.md) に沿ってコンソールの設定を確認してください。

## 1. メール／パスワード認証

1. [Firebase Console](https://console.firebase.google.com/project/sightseeing-matching-prototype/overview) で対象プロジェクトを開く。
2. 「構築」→「Authentication」→「始める」。
3. 「Sign-in method / ログイン方法」で「メール/パスワード」を有効化する。メールリンク方式は今回使用しない。
4. 「設定」→「パスワードポリシー」で最小文字数を **6** にする。大文字・小文字・数字・記号の必須条件はすべてオフにする。
5. Webの認証設定の「承認済みドメイン」を確認し、開発用の `localhost` と実際に利用するHostingドメインがなければ追加する。独自ドメインを使う場合も登録する。

閲覧・旅行計画では匿名認証は不要です。ゲストで写真を投稿する場合は匿名認証を有効化してください。写真投稿時のみFirebase匿名アカウントを作成します。登録後のメール確認は任意で、プロフィール画面から確認メールを送信できます。パスワード再設定メールも送信できます。

参考：[Flutterのメール／パスワード認証](https://firebase.google.com/docs/auth/flutter/password-auth)、[パスワードポリシー](https://firebase.google.com/docs/auth/web/password-auth)、[開発時のlocalhostの承認](https://firebase.google.com/docs/auth/web/email-link-auth)

## 2. プロフィール用Firestore

1. 「構築」→「Firestore Database」→「データベースの作成」。
2. Standard edition、データベースID **`(default)`** を使用する。
3. ロケーションを選ぶ。日本向けであれば `asia-northeast1`（東京）が候補。作成後の変更はできないため、運用先に合わせて選択する。
4. 本番モードで作成する。
5. 次のコマンドで、このプロジェクトの `firestore.rules` を反映する。Hostingの公開は含まない。

```sh
firebase login
firebase deploy --only firestore:rules --project sightseeing-matching-prototype
```

コンソールの「ルール」に `firestore.rules` の内容を貼って公開する方法でも構いません。登録ユーザー本人だけが `users/{自分のUID}` を取得・作成・編集・削除できます。ユーザー一覧や他人のプロフィールの取得、定義外のフィールドの保存は拒否します。コレクションやドキュメントの手動作成は不要です。

参考：[Firestoreのルール](https://firebase.google.com/docs/firestore/security/get-started)、[ロケーション](https://firebase.google.com/docs/firestore/locations)

## 保存する内容

| 保存先 | 内容 |
| --- | --- |
| Firebase Authentication | UID、メールアドレス、パスワードの認証情報、表示名、メール確認状態 |
| Firestore `users/{uid}` | `uid`, `nickname`, `ageGroup`, `prefecture`, `municipality`, `createdAt`, `updatedAt` |
| 端末内 | 旅行の基本設定・検索条件・旅程、ゲスト表示用ID |

パスワードをFirestoreやアプリ独自の端末ストレージに保存しません。メールアドレスはAuthから取得し、プロフィール用ドキュメントへ複製しません。年代は「10代以下／20代／30代／40代／50代／60代／70代以上」です。住所は地方を選択してから47都道府県のいずれかを選び、市町村を入力します。

登録済みユーザーの個人IDはFirebase Authの **UID** です。ニックネームは変更可能で、個人の識別キーには使いません。将来のフォローや共同旅程もUIDを参照する構成にできます。今回は公開プロフィール・共同編集・アカウント削除UIは実装していません。他人に公開する情報が必要になった場合は、住所などの非公開属性とは別のコレクションとルールを設計してください。

未登録の場合は「ゲストさん」と表示します。`guest-...` のIDを端末に保存し、同じブラウザ・同じオリジンでは再読み込みしても維持します。ブラウザのデータ削除や別端末への移動では維持されません。登録後はUIDが個人IDになります。

投稿本文・評価・写真URL・リアクションはFirestore、写真本体はStorageに保存します。未登録ユーザーは書き込み時にFirebase匿名認証のUIDを取得します。投稿の所有者判定にはFirebase UIDのみを使い、端末内ゲストIDを登録ユーザーの投稿IDへ読み替える処理はありません。

旅行の基本設定 `UserProfile` とアカウント属性 `AccountDetails` は別モデルです。旅程・検索条件・基本設定の端末内保存は維持します。認証セッションの復元はFirebase Auth SDKが管理します。


## 起動と手動確認

```sh
flutter pub get
flutter run -d chrome --web-port 7357
```

「プロフィール」→「登録する」から登録します。メール、6文字以上のパスワード、ニックネーム、年代、地方・都道府県、市町村を入力してください。登録後にプロフィールとUIDが表示されます。再読み込み、編集、ログアウト、再ログインも確認してください。ブラウザを終了して確認する場合は、同じブラウザプロファイル・オリジンを使用します。

Authの作成に成功しFirestoreの保存だけ失敗した場合、入力画面を保持してエラーを表示します。Firestoreの設定を直して再試行するか、プロフィールの「登録を完了する」から属性の登録を続けられます。認証設定の接続自体が失敗した場合もゲスト利用を継続でき、「アカウント機能に再接続」から再試行できます。

接続するFirebaseプロジェクトやネイティブのアプリIDを変更する場合は再生成してください。

```sh
flutterfire configure --project=sightseeing-matching-prototype --platforms=web,android,ios
```

## 本番にアカウントを作らず検証する

ターミナル1（Firebase CLIとJava 21以上が必要）：

```sh
firebase emulators:start --only auth,firestore,storage --project sightseeing-matching-prototype
```

このMacでシステムのJavaがない場合はAndroid Studio付属のJavaを使用できます。

```sh
export JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
export PATH="$JAVA_HOME/bin:$PATH"
firebase emulators:start --only auth,firestore,storage --project sightseeing-matching-prototype
```

ターミナル2：

```sh
flutter run -d chrome --web-port 7357 --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1
```

Authは9099、Firestoreは8080、管理画面は `http://127.0.0.1:4000` です。Android標準エミュレーターではホストに `10.0.2.2` を指定します。実機からは開発PCへ到達できるホスト設定が別途必要です。`FIREBASE_EMULATOR_HOST` を付けない通常起動は本番サービスに接続します。

Node.js 20以上があれば、次でローカルサービスへの登録・再ログインとFirestoreのアクセス制限を検証できます。テストで作成したローカルユーザー・ドキュメントは終了時に削除します。

```sh
node tool/check_auth_emulators.mjs
```

プロフィールUI・登録失敗時の入力保持・IDの所有判定等は `test/account_test.dart` と `test/account_widget_test.dart` にまとめています。

実際のFlutterFire Web SDKによる登録・属性編集・UIDを維持した再ログインは、エミュレーターを起動した状態で次の専用テストを実行します。通常の `flutter test` では実行しません。

```sh
flutter test --platform chrome --dart-define=AUTH_EMULATORS_TEST=true --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 test/account_browser_test.dart
```

観光地・交通・写真のクラウド移行と管理者設定は [クラウド移行ガイド](cloud_catalog_setup.md) を参照してください。エミュレーター検証時はStorageも同時に起動します。

## チャット・自治体ユーザの追加について

属性の保存先、管理者によるメールアドレス指定の変更、Cloud Functionsの反映手順は [chat_setup.md](chat_setup.md) を参照してください。Firestoreルールだけでなく、管理者用Functionのデプロイが必要です。
