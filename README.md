# TABISAKI — 観光地の発見と旅行作成

「まだ知らないワクワクを、自分だけの旅に。」興味を入口に北海道の体験を発見し、公共交通も使う旅を組み立てるFlutter UIプロトタイプです。

## 起動

```sh
flutter pub get
flutter run -d chrome --web-port 7357
```

同じブラウザの同じオリジン（スキーム・ホスト・ポート）で、再読み込み後も設定を復元します。Flutterが起動する一時Chromeプロファイルとは別に、普段のブラウザでアプリの再起動をまたいで保存を確認する場合は、次を実行して `http://localhost:7357` を開いてください。

```sh
flutter run -d web-server --web-port 7357
```

## アカウント登録（任意）

プロフィールタブからメール／パスワードで登録・ログインできます。年代・ニックネーム・地方／都道府県・市町村をFirestoreの本人専用ドキュメントへ保存し、個人IDにはFirebase AuthのUIDを使用します。未登録時は「ゲストさん」として旅行機能を利用できます。チャットはログイン・プロフィール登録後に利用できます。

Firebaseのアプリ接続設定は生成済みです。**利用前にAuthenticationの方式、Firestore・Storageの設定、セキュリティルールの反映を確認してください。** 詳しい手順とエミュレーターの使い方は [Firebase設定ガイド](docs/firebase_setup.md) を参照してください。旅行の基本設定や旅程は端末内保存、投稿はFirestore・Storage保存です。

## チャットとユーザー属性

「旅のしおり」右上のチャットボタンから表示名で相手を選び、1対1のテキストチャットができます。会話一覧・最新メッセージ・自治体／旅行者バッジはFirestoreの更新に連動します。一般ユーザが初期値で、属性を選択する登録項目はありません。

メール確認済みの管理者は「管理者メニュー→ユーザー属性」で登録メールを指定し、自治体ユーザに変更できます。安全なメール検索のためCloud Functionsを追加しました。反映手順と保存構造は [チャット設定ガイド](docs/chat_setup.md) を参照してください。

## 観光地・交通・写真のクラウド保存

通常の観光地・交通データはCloud Firestoreから取得します。写真本体はCloud Storage、写真URLと保存パスはFirestoreに保存します。新規画像はアップロード前に200KB以下へ変換し、表示時はURL単位のメモリ・永続キャッシュを利用します。管理者 `nichi-ka@nichi-ka.com` でログインすると、プロフィール最下部の「管理者メニュー」から観光地／交通の追加・編集・削除ができます。書き込みにはメール確認も必要です。

移行済みのFirestoreデータをそのまま利用します。ローカルMD・写真・解析処理・初回取り込み画面は削除済みです。カタログが空の場合にローカルデータで補完することもありません。

既存画像の200KB最適化、キャッシュ、Storageの設定、ルール反映の詳細は [クラウド移行ガイド](docs/cloud_catalog_setup.md) を参照してください。

## 操作

タブは「ホーム」「スワイプ」「旅のしおり」「旅程作成」「プロフィール」の5つです。旅程を作成済みなら「旅のしおり」、初回や観光地の保存だけの場合は「ホーム」から始まります。アプリ全体はオレンジと生成りのテーマです。AppBarの基本構成・完成したしおり・プロフィールの画面構成は再利用しています。

1. **ホーム**：登録済みの観光地写真と大きな見出し、写真を重ねた「興味から旅行を作る」カード、観光地4件のプレビュー。検索ボックスは置きません。プレビューには保存・詳細の操作を置きません。「もっと見る」でカード間隔8pxのコンパクトな2列一覧を開き、ハートで保存、カードのタップで既存の詳細シートを表示します。
2. **興味から旅行を作る**：既存の気分・理由・クエストの3問に、出発地、交通手段と旅行期間、日付、同行者の4ページを合わせた7問です。既存のDify推薦を縦リスト（最大10件）で表示します。推薦された段階では保存せず、ハートを押した観光地だけを候補にします。「保存した観光地で旅を作る」から、回答した条件を引き継いで旅程作成へ進みます。
3. **スワイプ**：「今日の偶然な発見」として、質問・AI推薦なしでカタログからランダムに最大10件を表示します。既存のPageViewで左右に移動し、上スワイプは保存して次へ、ハートは保存・解除です。最後には終了ページを表示します。写真の事前読み込みと既存のキャッシュを利用します。
4. **旅のしおり**：作成した旅行は従来の写真・タイムライン・詳細しおりで表示します。保存0件ならStep1から共通の質問へ、保存済みでも旅程未作成ならStep2から旅程入力へ案内します。右上から投稿・チャット、左上のDrawerから旅行の切替・名前変更・複製・削除を利用できます。
5. **旅程作成**：出発地・到着地はJR札幌駅、日付は今日、出発は8:00、泊数は日帰り、交通は公共交通が初期値です。検索から来た場合は回答した条件を優先します。泊数は半日・日帰りのみ選択でき、宿泊は対応予定です。保存した観光地を1件以上選ぶと、手動・AIのボタンを横並びで表示します。選択した地点だけで新しい旅程を作り、既存の編集画面へ進みます。AIは編集画面で既存の条件シートを開き、確定後に実行します。旅程ごとの1回制限は撤廃しました（処理中・結果不明の二重実行防止と既存の通信レート制限は維持）。
6. **プロフィール**：従来どおり、基本設定・アカウント・プリセット管理を利用できます。

## 旅のしおり内の投稿（Firestore）

「旅のしおり」右上の投稿ボタンから開きます。投稿画面の機能は従来どおりです。

- 「おすすめ」は質問の興味を参考に並べるルールベースのデモです。AI APIには接続していません。「フォロー中」はフォローしたユーザーのクラウド投稿を表示します。
- 投稿カードにはスポットタグ、写真のカルーセル、ページ表示、いいね、コメント、シェア、投稿の保存、星評価、本文・ハッシュタグ、最新コメントを表示します。
- タグをタップすると既存の観光地詳細が開き、同じスポットIDの投稿を「みんなのレビュー」に表示します。投稿のしおり保存と、旅行計画への体験保存は独立しています。
- 右下の＋から、登録済みスポット・評価・カテゴリ・本文を入力し、写真を選んで投稿できます。端末のライブラリ・対応端末での写真撮影を利用できます。
- 写真のみ最大6枚、1枚5MB未満（5,000,000バイト未満）。JPEG・PNG・WebP・GIFに対応します。動画は投稿できません。元のファイルサイズと画像内容を検証し、Storageルールでもサイズと形式を制限します。
- シェアは本文とスポット名のテキスト共有です。対応環境では標準の共有画面を使い、利用できない場合は本文をコピーします。公開用の投稿URLは生成しません。
- 投稿本文・評価・写真URL・コメント・いいねをFirestoreへ保存し、一覧をリアルタイム購読します。保存した投稿とフォローはユーザー別のFirestoreコレクションで管理します。
- 写真本体はCloud Storageです。投稿文書の保存失敗時はアップロード済み画像の削除を試み、入力を保持します。
- ゲストの書き込み時はFirebase匿名認証を使い、「ゲストさん」と表示します。他人の投稿変更や個人別の保存情報の読み取りはルールで拒否します。
- 投稿本文や投稿サンプルの自動生成、ローカル投稿DB、ローカル画像保存はありません。空のFirestoreでは空の一覧を表示します。
- 今回の対象外である旅程・検索条件・基本設定は従来の端末内保存を維持します。

詳しくは [クラウド保存と設定](docs/cloud_catalog_setup.md) を参照してください。

## 保存と独立性

- `UserProfile`：普段の基本設定。検索中やプリセット編集時の変更は反映しません。
- `SearchPreset`：名前とIDを持つ複数の条件。他のプリセットとは独立しています。
- `InterestAnswers`：気分・興味の理由・クエストの安定したID。検索条件とは別のモデルとして保持します。既存のDify接続へ回答内容と旅行条件を渡して推薦します。
- `SearchFilters`：既存の不変モデル`SearchConditions`を再利用する型名。出発地・交通・予算などを保持します。
- `LastSearch`：最後に探索へ進んだ条件とUTCの`searchedAt`。旧JSONの`executedAt`も読み込み可能です。
- 検索の交通手段は初期値を選択表示し、出発地・旅行期間・同行者は明示選択を記録します。戻る操作では表示を保持し、新しい検索ではリセットします。旅行期間・同行者は明示選択して検索へ進みます。
- 初期値は明示選択プリセット、明示選択した前回条件、通常検索時のプロフィール、デフォルト値の順です。
- 検索で選んだ旅行日と各条件は`itinerarySetupProvider`へ引き継ぎます。直接旅程作成タブを開いた場合は今日の日付を初期値にします。
- [`SharedPreferencesAsync`](https://pub.dev/packages/shared_preferences) とバージョン付きJSONを使用します。WebはlocalStorage、Android・iOSはプラットフォームの設定ストアを利用します。
- 保存処理はRepositoryに分離し、書き込みを直列化します。保存失敗時は成功扱いにせず入力を残します。不正なJSONや読み込みエラーも勝手に初期化・上書きしません。
- 旅程は既存の`TripState`を保存モデルとして再利用し、ID・タイトル・最終編集日時を追加しました。旅のしおりは同じ旅程一覧を表示し、表示専用の旅程コピーは保存しません。
- 旅程・保存体験・訪問順・旅行日・条件を`tabisaki.trips.v1`のJSONへ自動保存します。プロフィール等の既存データキーとは分離しています。起動時に両方を復元してからホームを表示します。
- 旅のしおりは保存済みの選択IDを最優先します。選択IDが無効なら、今日以降で最も近い旅行、日程未定で最後に編集した旅行、その他の保存済み旅行の順に選び直します。選択IDを保存し、再起動後も過去の旅や作成途中の旅を含めて同じ旅を開きます。最後の旅を削除すると一覧と選択IDを空にします。
- 「旅程を編集する」は表示中の旅程を既存エディターへ渡し、「旅のしおりを開く」は既存の詳細画面を開きます。Drawerの各旅程の「…」から名前変更・独立したコピーの作成・確認付き削除ができます。選択中以外の旅を削除しても現在の表示は変わりません。スポットの削除・並べ替えは既存エディターを利用します。
- 観光地のお気に入りは`TripLibrary.savedSpots`にまとめ、一覧・AI推薦・スワイプ・詳細で共通利用します。旧データにこのフィールドがなければ、各旅程の保存済み観光地をIDでまとめて読み込みます。保存や検索では旅程を作成・変更せず、入力画面の作成ボタンを押したときだけ新しい旅程を追加します。旅行を削除しても共通のお気に入りは残り、保存を解除しても作成済み旅程の訪問先は消しません。
- 旅のしおりは訪問順だけを表示し、架空の訪問時刻は付けません。日程未定は「日程未定」、公共交通区間は「経路未確認」と明示します。詳細画面の時刻等は従来どおりサンプルです。
- 旅程の書き込みは直列化し、失敗時は画面上部に再試行案内を表示します。読み込みエラー時に保存データを勝手に消しません。
- 質問途中の回答・旅程作成前の入力条件と選択はメモリ内です。お気に入りと作成した旅程は従来の保存キーへ永続化します。

## 構成と変更ファイル

画面は5タブと共通画面に分離しています。配置・入口・依存方向は[画面構成ガイド](lib/screen/README.md)を参照してください。従来のホームは`bookmark/bookmark_home.dart`へ移動し、`home/home_screen.dart`は新ホームの入口です。

| ファイル | 役割 |
| --- | --- |
| `lib/theme/app_theme.dart` | オレンジ基調の共通テーマと配色 |
| `lib/model/search_settings.dart` | 条件・UserProfile・SearchPreset・LastSearch、UTC保存と旧日時の互換読み込み |
| `lib/model/trip_plan.dart` | 既存TripStateの保存可能なモデルと、選択IDとフォールバック規則を持つTripLibrary |
| `lib/model/interest_answers.dart` | 3問の回答を検索条件から分離 |
| `lib/repository/trips_repository.dart` | SharedPreferencesAsyncによる旅程一覧のJSON保存 |
| `lib/repository/settings_repository.dart` | 保存RepositoryとSharedPreferencesAsyncアダプター |
| `lib/state/search_selection_state.dart` | 初期値と独立した、ユーザーが明示選択した項目の表示状態 |
| `lib/state/settings_state.dart` | 復元・保存・検索条件の編集状態 |
| `lib/state/discovery_state.dart` | 検索画面遷移・質問回答・探索位置 |
| `lib/state/trip_state.dart` | 編集中旅程の投影と、既存画面から使う編集API |
| `lib/state/trip_library_state.dart` | 旅程一覧の復元・編集・削除・保存とエラー通知 |
| `lib/navigation/travel_navigation.dart` | 質問開始・保存した観光地から旅程作成への共通遷移 |
| `lib/state/ai_trip_state.dart` | AI作成の要求・結果購読 |
| `lib/state/swipe_state.dart` | ランダムなスワイプの独立した状態 |
| `lib/state/app_tab.dart` | ホーム・スワイプ・旅のしおり・旅程作成・プロフィールの5タブ |
| `lib/service/curiosity_questions.dart` | 4つの気分・12通りの理由・5種類のクエストセットと興味のヒント |
| `lib/screen/shared/discovery/widgets/curiosity_question_flow.dart` | アイコン付き4択・理由3択・クエスト3択の質問UI |
| `lib/service/recommendation_service.dart` | 好みに近い・隣接・意外な体験を混ぜる推薦 |
| `lib/service/mock_access_ranking.dart` | 条件からサンプルのアクセスしやすさを算出し、ジャンル内を並べ替え |
| `lib/service/search_execution_service.dart` | 入力確定・プリセットとLastSearchの一括保存・旅程引継ぎ・探索開始 |
| `lib/screen/home/home_screen.dart` | ホームタブの入口・共通の質問フローとの切替 |
| `lib/screen/home/home_overview.dart` | 新しいホームの概要画面 |
| `lib/screen/shared/experiences/places_catalog_screen.dart` | 2列の観光地一覧 |
| `lib/screen/shared/discovery/recommended_places_list.dart` | AI推薦の縦リストと共通保存 |
| `lib/screen/swipe/swipe_home.dart` | 独立したランダム10件のカードセッション |
| `lib/screen/bookmark/bookmark_home.dart` | 選択中のしおり・全スポットをスクロールできるタイムライン・空状態と既存画面への導線 |
| `lib/screen/shared/trips/trips_drawer.dart` | 旅程一覧・切り替え・名前変更・複製・確認付き削除 |
| `lib/screen/shared/discovery/interest_search_flow.dart` | 共通の7つの質問・AIおすすめ一覧へのフロー |
| `lib/screen/shared/discovery/search_conditions_screen.dart` | 4画面の進捗・固定ボタン・保存して検索 |
| `lib/screen/shared/discovery/widgets/conditions_step_pages.dart` | 検索専用の出発地・交通と期間・日付・同行者ページ（共通フォームやプロフィールは変更なし） |
| `lib/state/conditions_step_state.dart` | 条件入力ステップの表示位置。編集値は既存のsearchDraftProviderで共通保持 |
| `lib/screen/profile/profile_home.dart` | プロフィールとプリセットの管理・編集 |
| `lib/screen/profile/widgets/conditions_form.dart` | プロフィール基本設定・保存プリセット編集用の共通入力UI（検索フローとは別） |
| `lib/data/departure_places.dart` | 駅・バス停のローカル候補と概略座標 |
| `lib/widgets/departure_map.dart` | flutter_map・OpenStreetMap地図、選択ピン、障害時の案内 |
| `lib/widgets/settings_actions.dart` | プリセット名ダイアログ・結果通知 |
| `lib/screen/shared/experiences/widgets/experience_deck.dart` | 事前読み込み済み画像の左右スワイプ探索 |
| `lib/screen/shared/experiences/experience_detail.dart` | ストーリー詳細、固定の閉じるボタン |
| `lib/screen/itinerary/itinerary_home.dart` | 旅程入力と従来の編集画面の切替 |
| `lib/screen/itinerary/itinerary_setup_screen.dart` | デフォルト値付きの旅程入力・保存した観光地の選択 |
| `lib/state/itinerary_setup_state.dart` | 作成前の条件・選択と検索からの引継ぎ |
| `lib/screen/base_page.dart` | 起動時復元・旅行作成状況による初期タブ・5タブと戻る操作 |
| `lib/data/catalog_data.dart` | FirestoreカタログRepositoryと読み込み状態のRiverpod Provider |
| `lib/repository/catalog_repository.dart` | カタログ取得のインターフェース |
| `lib/model/travel_catalog.dart` | 体験一覧・交通情報と区間の表示モデル |
| `pubspec.yaml`, `pubspec.lock` | 保存・地図・座標型・地図出典リンクの依存 |
| `android/app/src/main/AndroidManifest.xml` | リリース版でも地図画像を取得するためのINTERNET権限 |
| `ios/Podfile`, `ios/Flutter/{Debug,Release}.xcconfig` | プラグイン導入時にFlutterが生成したiOS設定 |
| `test/*` | 保存・分岐・全画面操作・Chrome実ストレージ検証 |

既存のMaterial 3、HookConsumerWidget / Riverpod、中央最大480pxレイアウト、写真失敗時表示、長押し詳細、ドラッグ並べ替えを活用しています。

## 制限・未実装

- Firebase Authentication、本人用プロフィール・観光地・交通のFirestore保存、写真のCloud Storage保存を使用します。AI・交通API・課金、公開プロフィール、共同旅程、旅程のクラウド同期は未実装です。
- 出発地・交通手段・予算・移動時間などはサンプル推薦のジャンル内順位に反映します。実経路や料金の検索ではなく、条件を満たす保証・除外判定は行いません。
- [flutter_map](https://pub.dev/packages/flutter_map)でパン・ズームできる地図を表示します。地図画像はOpenStreetMapから取得しますが、駅・バス停候補と座標はローカルのサンプルです。外部ジオコーディングや全国の駅検索はありません。検索フローで新しく選べる地点は暫定の4地点です。画像取得失敗時も4択ボタンを利用できます。保存済み条件に別の出発地がある場合は、自動変更せず保持します。地図には出典リンクを表示しています。
- 時刻・乗換・徒歩・交通費・車の所要時間はすべてダミー。帰路や最終便、実際の日帰り可否も検索しません。
- 旅行期間は保存・引継ぎ・表示する段階です。複数日の割当や宿泊施設の予約・検索は実装していません。AI提案も固定の夕張3件を使う「デモ用の旅程」です。
- 観光体験の提供状況・営業時間は未確認。Unsplashの写真も場所を特定しないイメージです。
- 複数タブ・複数端末間の同期や同時編集の競合解決は対象外です。
- Android/iOSの実機ビルドは未検証です。

## 検証

投稿は `test/posts_state_test.dart`・`test/posts_widget_test.dart` で操作・レビュー連動を、`test/cloud_catalog_browser_test.dart` で実際のFirestoreへの保存・別クライアントによる再取得・権限を確認します。

```sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter test --platform chrome test/browser_storage_test.dart
dart run tool/build_web.dart
node tool/check_web_release.mjs --local-build
```

既存のテストには、JSON保存層の復元・独立性・保存失敗・旧日時の移行・UTC・質問先行フロー・条件入力・プロフィールとプリセットCRUDなどの検証があります。画面テストでは地図タイルを無効にし、出発地の4択・地図の開閉・ピンの確認・ズーム・連続タップ・小型Android相当画面も扱います。Chrome専用テストでは実際のWebアダプターで保存・復元を確認します（通常のVMテストではChrome専用の2件をスキップ）。質問・推薦のテストも現在の4×3×3の構成に合わせています。

ホーム・旅程管理のテストでは、選択IDの復元、過去の旅の選択、日程未定・スポット0件、コピーの独立性、削除後の選択、最後の旅の削除、新規検索時の既存旅程保護、Drawer操作と小型Android相当レイアウトを確認します。Android実機での確認は未実施です。
