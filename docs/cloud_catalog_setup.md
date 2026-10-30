# 観光地・交通・投稿のクラウド保存

チャットと管理者によるユーザー属性変更の設定は [chat_setup.md](chat_setup.md) を参照してください。

## 保存先

| 内容 | 保存先 |
| --- | --- |
| 観光地・代表／補足写真のURL・保存パス | Firestore `sightseeing_spot/{id}` |
| 交通・写真のURL・保存パス | Firestore `transit/{id}` |
| 観光地・交通の写真本体 | Storage `catalog/{sightseeing_spot または transit}/{id}/{file}` |
| 投稿本文・評価・カテゴリ・投稿者UID／名前・写真URL・日時 | Firestore `posts/{id}` |
| コメント | Firestore `post_comments/{id}` |
| いいね | Firestore `post_likes/{postId}_{uid}` |
| 保存した投稿 | Firestore `users/{uid}/post_bookmarks/{postId}` |
| フォロー | Firestore `users/{uid}/post_follows/{targetUid}` |
| 投稿写真本体 | Storage `posts/{uid}/{postId}/{file}` |

観光地・交通・投稿はクラウドのみを参照します。ローカルのMD・写真・解析処理・取り込み処理と、投稿用IndexedDB／Sembastは削除しています。投稿や本文のサンプルを自動生成しません。空のFirestoreでは空の一覧を表示します。

今回の対象外である旅程・検索条件・旅行の基本設定の端末内保存は維持します。写真選択中のプレビューと未送信テキストは画面のメモリ内に保持します。画像の表示には専用の破棄可能なキャッシュを使用します。データの正本はクラウドです。認証セッション管理はSDK標準の動作です。

旧端末内の投稿は読み込まず、自動公開・自動移行もしません。削除済みの投稿用ローカルDBを復元する経路はありません。この変更で本番のFirestore／Storageの既存データは削除しません。

## Firebase設定

接続先は `sightseeing-matching-prototype`。FirestoreとStorageに既に移行した観光地・交通をそのまま利用します。管理画面からのMD取り込みは廃止しました。

新しい投稿用ルールを反映してください。Hostingの公開は含みません。

```sh
firebase deploy --only firestore:rules,storage --project sightseeing-matching-prototype
```

本コード改修ではルールの本番反映を実行していません。Firestoreの新しいコレクションを手動で作成する必要はありません。投稿時に自動作成されます。

- Authenticationのメール／パスワードを有効化する。ゲストの投稿・いいね・コメント・保存・フォローも使う場合は匿名認証を有効化する。閲覧・旅程作成だけなら匿名認証は不要。
- Cloud Storageを有効化する。設定済みのバケットは `sightseeing-matching-prototype.firebasestorage.app`。
- 現在のStorage利用要件はBlazeプラン。[公式の要件](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)

### Webの画像取得に必要なCORS設定

画像を直接ブラウザで開けても、Webアプリから画像データを取得・キャッシュするにはStorageバケットのCORS設定が必要です。未設定の場合、Chromeは `No 'Access-Control-Allow-Origin' header` として取得を拒否し、アプリではプレースホルダーが表示されます。端末のキャッシュ削除だけでは直りません。[Firebase公式の説明](https://firebase.google.com/docs/storage/web/download-files#cors_configuration)

リポジトリ直下で、Google Cloud CLIを利用できるアカウントから次を実行してください。バケット設定の変更権限が必要です。`firebase deploy` はCORS設定を反映しません。

```sh
gcloud storage buckets update gs://sightseeing-matching-prototype.firebasestorage.app --cors-file=storage.cors.json
gcloud storage buckets describe gs://sightseeing-matching-prototype.firebasestorage.app --format="default(cors_config)"
node tool/check_image_cors.mjs http://localhost:7357
```

Google Cloud CLIが手元にない場合は、Google CloudコンソールのCloud Shellで、次のコマンドを実行できます。

```sh
cat > /tmp/tabisaki-storage.cors.json <<'JSON'
[{"origin":["*"],"method":["GET","HEAD"],"responseHeader":["Content-Type","Content-Length","Cache-Control","ETag"],"maxAgeSeconds":3600}]
JSON
gcloud storage buckets update gs://sightseeing-matching-prototype.firebasestorage.app --cors-file=/tmp/tabisaki-storage.cors.json
```

これは閲覧用のGET・HEADのみを許可します。既存の公開画像を開発時の可変ポートからも取得できるよう、オリジンは `*` としています。Storageルールや認証、書き込み権限は変更しません。既存のCORS設定がある場合、このコマンドはその設定を置き換えるため、必要な許可を統合してから反映してください。本番オリジンと開発ポートを固定した段階では `origin` を使用するオリジンの一覧に限定できます。

反映後、Web画面を再読み込みしてください。バケット設定は今回のローカル修正では変更していません。確認用スクリプトは公開カタログの画像1件の応答を確認するだけで、クラウドへの書き込みや画像URLのログ出力は行いません。

## 管理画面

`nichi-ka@nichi-ka.com` でログインすると、プロフィール最下部に管理者メニューを表示します。書き込みにはメール確認も必要です。「確認メールを送信」→確認リンク→「確認状態を更新」の順で、認証トークンも更新します。

「観光地情報／交通情報」のタブから追加・編集・削除します。IDは変更できず、既存IDをそのまま使います。新規IDは英数字で始まる1〜80文字で、英数字・半角スペース・ハイフン・アンダースコアを使えます。観光地は代表1枚＋補足5枚、交通は写真1枚までです。

交通時刻は0時からの分数で編集します（10:30=630、翌日1:00=1500）。`position` は `first`／`following`／`any`、`spotId` は観光地IDまたは共通の `*` です。現行の交通情報は引き続きサンプルで、実際の運行可否を保証しません。

## 投稿の動作と権限

公開投稿の本文・評価・写真・コメント・いいねは複数端末／ユーザー間で取得できます。投稿一覧と観光地・交通のカタログはFirestoreをリアルタイム購読します。投稿がなければ空状態です。「おすすめ」は既存の質問による並び替えで、AI APIには接続していません。

画像はJPEG・PNG・WebP・GIFのみ、最大6枚、1枚 **5,000,000バイト未満**。ちょうど5MBも拒否します。選択時と送信前に元サイズ・画像形式・デコードを確認します。アップロード前に表示用JPEGへ変換し、200,000バイト以下・長辺1280px以下にします。Storageルールでも200KB超の新規保存を拒否します。GIFは先頭フレームの静止画、透過部分は白背景になります。画像本体はFirestoreの1MiB制限を避けるためStorageに保存します。[Firestore上限](https://firebase.google.com/docs/firestore/quotas)

- ゲストの書き込み時のみ匿名認証でUIDを取得し、名前を「ゲストさん」とする。その後同じセッションからメール登録すると認証方式をリンクし、UIDを維持する。
- 投稿者UIDの偽装・他人の本文変更・他人の投稿削除をルールで拒否する。
- コメントといいねは本人のUIDでのみ作成できる。投稿本文は新規作成時に保存し、本文編集機能は今回追加しない。
- ブックマークとフォローの読み書きは本人のみ。別のユーザーが取得することはできない。アカウントを切り替えると購読先も切り替える。
- 投稿削除は削除中フラグ→関連コメント・いいねの削除→投稿文書の削除→画像削除の順。削除中の投稿への新規コメント・いいねを禁止し、失敗時は可能ならフラグを戻す。
- 他ユーザーが保存していた削除済み投稿の参照は本人のコレクションに残る場合があるが、画面には表示しない。個人情報のコレクションを横断して削除する処理は行わない。

画像とFirestoreは別サービスなので1トランザクションにはできません。画像をアップロードしてから投稿文書を作成し、作成失敗時はその試行の画像削除を試みます。通信切断・権限変更等で残った未参照ファイルはStorageで確認できます。投稿本文の失敗時は画面入力を保持し、成功扱いにしません。

現在の投稿一覧は最新100件です。コメント・いいねは別コレクションの購読結果を合成し、人数や件数をクライアントの任意入力に頼らず表示します。大量投稿に対するページ分割や集計用バックエンドは今回の対象外です。

## 画像の通信量削減

- 表示用画像は **200KB以下（200,000バイト以下）**。入力は従来どおり5MB未満で、圧縮前の5MB以上は受け付けません。画質と画像寸法を調整し、EXIF等を除去してJPEGにします。
- 全画面の画像は同じキャッシュ経由で読み込みます。Flutterのデコード済み画像キャッシュに加え、WebはCache Storage、Android/iOSはアプリのキャッシュディレクトリに最大320枚（約64MB）を保存します。メモリ内の圧縮画像は最大64枚です。
- 同じURLがキャッシュにある場合、StorageへのGET・HEAD・メタデータ照会をしません。ページ移動・再起動・メモリ上の画像破棄後も永続キャッシュを再利用します。同時に同じ画像を要求しても取得を1回にまとめます。
- アプリ内の画像更新では新しいStorageファイルとURLを作ります。FirestoreのURL変更を購読して新しい画像だけを取得し、説明や交通情報だけの変更では画像を再取得しません。新規ファイルには `public,max-age=31536000,immutable` を設定します。
- 初回取得、キャッシュ削除、OS／ブラウザの容量制限による破棄後は再取得します。利用できない保存領域ではメモリキャッシュへ切り替えます。変更検知や認証に必要なFirestore／Authの通信自体は残ります。
- URLを変えずにStorageコンソールから画像を上書きすると変更を検知できません。画像は管理画面から更新し、新URLで差し替えてください。

### 既に保存してある大きな画像

今回のコード変更だけでは、既存オブジェクトのサイズは変わりません。ルールを反映後、確認済み管理者でプロフィール→管理者メニュー→右上の圧縮アイコン **「既存画像を200KB以下に最適化」** を実行してください。

観光地・交通・全ユーザーの投稿を処理し、大きな画像を一度取得して200KB以下の派生画像を保存します。画像URLと保存パスだけを更新し、投稿本文・投稿者・評価は維持します。200KB以下の画像はスキップし、再実行しても重複作成しません。旧画像はURL互換のため残し、今回の最適化では削除しません。

他ユーザーの投稿に対する管理者権限は、表示画像の置換と `display-v1-...` という200KB以下のJPEGファイルの作成／削除に限定しています。本文や評価の変更・他人の投稿削除は許可しません。処理中に画像参照が変わった文書は上書きせず、失敗として再実行できる形にしています。

既存画像の最適化前は、その元画像を初回だけ取得して端末内で200KB以下へ変換・キャッシュします。この場合、初回のダウンロード量は元画像サイズです。**最初の取得から200KB以下にするにはクラウド側の最適化を先に実行してください。** 最適化の作業自体にも一度だけ元画像の転送が発生します。

### 最初の3問

気分・理由・クエストは、写真を読み込まずMaterialアイコンとテキストだけで表示します。回答ID・分岐・スライドアニメーション・推薦処理は維持しています。

## 検証

```sh
firebase emulators:start --only auth,firestore,storage --project sightseeing-matching-prototype
flutter run -d chrome --web-port 7357 --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1
```

Java 21以上が必要です。このMacでは `JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home'` を利用できます。Auth:9099、Firestore:8080、Storage:9199、管理UI:4000です。

```sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter test --platform chrome test/image_cache_browser_test.dart
flutter test --platform chrome --dart-define=AUTH_EMULATORS_TEST=true --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 test/cloud_catalog_browser_test.dart
node tool/check_cloud_emulators.mjs
flutter build web
```

ブラウザテストは2つの実Firebaseクライアントを使い、投稿の再取得、別ユーザーのコメント・いいね、個人別の保存・フォロー、権限、削除を確認します。テスト用の投稿・ユーザーはローカルにのみ作成します。専用の空のエミュレーターで、各コマンドを順番に実行してください。
