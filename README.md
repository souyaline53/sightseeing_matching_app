# TABISAKI — 検索フロー統合プロトタイプ

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

## 操作

1. ホームの「検索を開始する」でプロフィールを初期条件として読み込み、まず3つの好奇心質問へ進みます。「前回の条件で探す」やプロフィールのプリセット読み込みも、質問から始まります。
2. 質問1は写真付きの6つの気分、質問2・3の既存の分岐は維持しています。質問3の回答後に条件設定へ進み、質問の回答は条件の編集や戻る操作でも保持します。
3. 全画面の条件設定は、STEP 1「どこから旅を始める？」→STEP 2「どうやって旅する？」→STEP 3「旅の条件を決めよう」の順です。出発地のチップ・ローカル検索候補はワンタップで確定し、地図のピンは選択後「この出発地にする」で確定します。移動手段もカードを1回タップするだけで次へ進みます。
4. STEP 3は片道時間、旅行期間、総予算、同行者、折りたたみの徒歩負担を編集できます。「この条件で探す」で編集値を確定し、「詳細設定をスキップ」では検索開始時の初期詳細条件を使います。スキップでもSTEP 1・2で選んだ出発地・移動手段は保持します。「この条件を保存」は編集値を名前付きプリセットに保存します。探索へ進む時点だけLastSearchを更新し、`searchedAt`をUTCで記録します。検索フローでは旅行日を聞きません。
5. 探索画面は全10件の写真を事前に読み込みます。最大12秒で個々の失敗をプレースホルダーに確定し、スワイプ中には読み込み直しません。**左スワイプは次へ、右スワイプは保存して次へ**。ハートは保存のみ。最後の次は先頭へ循環します。上下スワイプには操作を割り当てていません。詳細は長押しまたは画像上のボタンで表示します。
6. 「旅行計画へ」または「旅を組み立てる」タブから、保存した体験を追加・削除・ドラッグ並べ替えします。自分で組み立てた旅程とAIのデモ用旅程を表示できます。タブを切り替えても編集中の旅程を保持します。
7. プロフィールでは普段の出発地・交通手段・予算・徒歩希望を保存します。プリセットの読み込み、名前変更、内容編集、上書き、確認付き削除もここから行います。

## 保存と独立性

- `UserProfile`：普段の基本設定。検索中やプリセット編集時の変更は反映しません。
- `SearchPreset`：名前とIDを持つ複数の条件。他のプリセットとは独立しています。
- `InterestAnswers`：今回の気分と二択2問の回答。検索条件とは別のモデルとして保持します。
- `SearchFilters`：既存の不変モデル`SearchConditions`を再利用する型名。出発地・交通・予算などを保持します。
- `LastSearch`：最後に探索へ進んだ条件とUTCの`searchedAt`。旧JSONの`executedAt`も読み込み可能です。
- 初期値は明示選択プリセット、明示選択した前回条件、通常検索時のプロフィール、デフォルト値の順です。
- 検索実行日時を旅行日には使いません。旅程側の`travelDate`は別のnullable値で、新しい検索では未確定に戻します。旅行日選択は既存の旅程画面で行います。旧プリセットの`dateChoice`/`fixedDate`は互換性のため保持しますが、新しい検索では参照・検証しません。
- [`SharedPreferencesAsync`](https://pub.dev/packages/shared_preferences) とバージョン付きJSONを使用します。WebはlocalStorage、Android・iOSはプラットフォームの設定ストアを利用します。
- 保存処理はRepositoryに分離し、書き込みを直列化します。保存失敗時は成功扱いにせず入力を残します。不正なJSONや読み込みエラーも勝手に初期化・上書きしません。
- 保存済みの体験カード、質問途中の回答、編集途中の検索条件・旅程はメモリ内の状態で、ページ再読み込みではリセットされます。永続化対象は上記3種類です。

## 構成と変更ファイル

| ファイル | 役割 |
| --- | --- |
| `lib/model/search_settings.dart` | 条件・UserProfile・SearchPreset・LastSearch、UTC保存と旧日時の互換読み込み |
| `lib/model/interest_answers.dart` | 3問の回答を検索条件から分離 |
| `lib/repository/settings_repository.dart` | 保存RepositoryとSharedPreferencesAsyncアダプター |
| `lib/state/settings_state.dart` | 復元・保存・検索条件の編集状態 |
| `lib/state/discovery_state.dart` | 検索画面遷移・質問回答・探索位置 |
| `lib/state/trip_state.dart` | 保存体験・訪問順・旅程条件 |
| `lib/state/app_tab.dart` | 発見・旅程・プロフィールの3タブ |
| `lib/service/curiosity_questions.dart` | 気分別6分岐・質問2の回答別12分岐 |
| `lib/service/recommendation_service.dart` | 好みに近い・隣接・意外な体験を混ぜる推薦 |
| `lib/service/mock_access_ranking.dart` | 条件からサンプルのアクセスしやすさを算出し、ジャンル内を並べ替え |
| `lib/service/search_execution_service.dart` | 入力確定・スキップ・LastSearch保存・旅程引継ぎ・探索開始を一括処理 |
| `lib/screen/recommendation/recommendation_home.dart` | ホームと3問のフロー |
| `lib/screen/search/search_conditions_screen.dart` | 3ステップの進捗・固定ボタン・保存 |
| `lib/screen/search/conditions_step_pages.dart` | 検索専用の出発地・移動手段・詳細条件ページ（共通フォームやプロフィールは変更なし） |
| `lib/state/conditions_step_state.dart` | 条件入力ステップの表示位置。編集値は既存のsearchDraftProviderで共通保持 |
| `lib/screen/profile/profile_home.dart` | プロフィールとプリセットの管理・編集 |
| `lib/widgets/conditions_form.dart` | プロフィール・条件・プリセット共通の入力UI |
| `lib/data/departure_places.dart` | 駅・バス停のローカル候補と概略座標 |
| `lib/widgets/departure_map.dart` | flutter_map・OpenStreetMap地図、選択ピン、障害時の案内 |
| `lib/widgets/settings_actions.dart` | プリセット名ダイアログ・結果通知 |
| `lib/screen/recommendation/experience_deck.dart` | 事前読み込み済み画像の左右スワイプ探索 |
| `lib/screen/recommendation/experience_detail.dart` | ストーリー詳細、固定の閉じるボタン |
| `lib/screen/itinerary/itinerary_home.dart` | 条件を引き継いだ旅程編集とサンプル交通 |
| `lib/screen/base_page.dart` | 起動時復元・3タブ・戻る操作 |
| `lib/data/mock_data.dart` | 北海道10件とサンプル交通。推薦処理はServiceに分離 |
| `pubspec.yaml`, `pubspec.lock` | 保存・地図・座標型・地図出典リンクの依存 |
| `android/app/src/main/AndroidManifest.xml` | リリース版でも地図画像を取得するためのINTERNET権限 |
| `ios/Podfile`, `ios/Flutter/{Debug,Release}.xcconfig` | プラグイン導入時にFlutterが生成したiOS設定 |
| `test/*` | 保存・分岐・全画面操作・Chrome実ストレージ検証 |

既存のMaterial 3、HookConsumerWidget / Riverpod、中央最大480pxレイアウト、写真失敗時表示、長押し詳細、ドラッグ並べ替えを活用しています。

## 制限・未実装

- AI・交通API・Firebase・認証・課金は追加していません。
- 出発地・交通手段・予算・移動時間などはサンプル推薦のジャンル内順位に反映します。実経路や料金の検索ではなく、条件を満たす保証・除外判定は行いません。
- [flutter_map](https://pub.dev/packages/flutter_map)でパン・ズームできる地図を表示します。地図画像はOpenStreetMapから取得しますが、駅・バス停候補と座標はローカルのサンプルです。外部ジオコーディングや全国の駅検索はありません。任意の地域名は直接入力できます。画像取得失敗時も候補・直接入力・ピン選択を利用できます。地図には出典リンクを表示しています。
- 時刻・乗換・徒歩・交通費・車の所要時間はすべてダミー。帰路や最終便、実際の日帰り可否も検索しません。
- 旅行期間は保存・引継ぎ・表示する段階です。複数日の割当や宿泊施設の予約・検索は実装していません。AI提案も固定の夕張3件を使う「デモ用の旅程」です。
- 観光体験の提供状況・営業時間は未確認。Unsplashの写真も場所を特定しないイメージです。
- 複数タブ・複数端末間の同期や同時編集の競合解決は対象外です。
- Android/iOSの実機ビルドは未検証です。

## 検証

```sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter test --platform chrome test/browser_storage_test.dart test/conditions_steps_test.dart
flutter build web
```

通常テストではJSON保存層をメモリストアに差し替え、復元・独立性・保存失敗・旧日時の移行・UTC・全24通りの推薦・質問先行フロー・スキップ・プロフィールとプリセットCRUDを検証します。画面テストでは地図タイルを無効にし、画像がない場合の候補選択・ピンの明示確認・ズーム・連続タップ・小型Android相当画面のキーボード表示も検証します。Chrome専用テストでは実際のWebアダプターで保存・復元を確認します（通常のVMテストでは1件スキップ）。
