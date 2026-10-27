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

1. ホームの「検索を開始する」でプロフィールの基本設定を使って条件設定へ進みます。「前回の条件で探す」は前回の検索がある場合のみ表示します。
2. 条件は独立した全画面で編集します。出発地、旅行日、移動手段、期間、交通費を含む総予算、片道時間、徒歩負担、同行者を設定できます。「この条件を保存」で名前付きプリセットを追加できます。空の名前は「いつもの旅」になります。
3. 質問1は写真付きの6つの気分、質問2は気分別の二択、質問3はさらに質問2の結果で変わる二択です。戻る操作で回答と入力を保持し、前の回答を変更した場合は影響する後続回答を更新します。
4. 質問3に答えて探索に進む時点で、LastSearchを自動保存し、旅行条件を旅程へ引き継ぎます。条件画面を開いただけではLastSearchを更新しません。
5. 探索画面は全10件の写真を事前に読み込みます。最大12秒で個々の失敗をプレースホルダーに確定し、スワイプ中には読み込み直しません。**左スワイプは次へ、右スワイプは保存して次へ**。ハートは保存のみ。最後の次は先頭へ循環します。上下スワイプには操作を割り当てていません。詳細は長押しまたは画像上のボタンで表示します。
6. 「旅行計画へ」または「旅を組み立てる」タブから、保存した体験を追加・削除・ドラッグ並べ替えします。自分で組み立てた旅程とAIのデモ用旅程を表示できます。タブを切り替えても編集中の旅程を保持します。
7. プロフィールでは普段の出発地・交通手段・予算・徒歩希望を保存します。プリセットの読み込み、名前変更、内容編集、上書き、確認付き削除もここから行います。

## 保存と独立性

- `UserProfile`：普段の基本設定。検索中やプリセット編集時の変更は反映しません。
- `SearchPreset`：名前とIDを持つ複数の条件。他のプリセットとは独立しています。
- `LastSearch`：最後に探索へ進んだ条件と実行日時。
- 初期値は明示選択プリセット、明示選択した前回条件、通常検索時のプロフィール、デフォルト値の順です。
- 「明日」は検索時点の翌日。「週末」は次の土曜日（土曜日当日は当日、日曜日は翌週土曜日）です。固定日付が過去の場合は選び直すまで先へ進めません。
- [`SharedPreferencesAsync`](https://pub.dev/packages/shared_preferences) とバージョン付きJSONを使用します。WebはlocalStorage、Android・iOSはプラットフォームの設定ストアを利用します。
- 保存処理はRepositoryに分離し、書き込みを直列化します。保存失敗時は成功扱いにせず入力を残します。不正なJSONや読み込みエラーも勝手に初期化・上書きしません。
- 保存済みの体験カード、質問途中の回答、編集途中の検索条件・旅程はメモリ内の状態で、ページ再読み込みではリセットされます。永続化対象は上記3種類です。

## 構成と変更ファイル

| ファイル | 役割 |
| --- | --- |
| `lib/model/search_settings.dart` | 条件・UserProfile・SearchPreset・LastSearchの不変モデル、JSON、日付検証 |
| `lib/repository/settings_repository.dart` | 保存RepositoryとSharedPreferencesAsyncアダプター |
| `lib/state/settings_state.dart` | 復元・保存・検索条件の編集状態 |
| `lib/state/discovery_state.dart` | 検索画面遷移・質問回答・探索位置 |
| `lib/state/trip_state.dart` | 保存体験・訪問順・旅程条件 |
| `lib/state/app_tab.dart` | 発見・旅程・プロフィールの3タブ |
| `lib/service/curiosity_questions.dart` | 気分別6分岐・質問2の回答別12分岐 |
| `lib/service/recommendation_service.dart` | 好みに近い・隣接・意外な体験を混ぜる推薦 |
| `lib/screen/recommendation/recommendation_home.dart` | ホームと3問のフロー |
| `lib/screen/search/search_conditions_screen.dart` | 全画面の条件設定 |
| `lib/screen/profile/profile_home.dart` | プロフィールとプリセットの管理・編集 |
| `lib/widgets/conditions_form.dart` | プロフィール・条件・プリセット共通の入力UI |
| `lib/widgets/settings_actions.dart` | プリセット名ダイアログ・結果通知 |
| `lib/screen/recommendation/experience_deck.dart` | 事前読み込み済み画像の左右スワイプ探索 |
| `lib/screen/recommendation/experience_detail.dart` | ストーリー詳細、固定の閉じるボタン |
| `lib/screen/itinerary/itinerary_home.dart` | 条件を引き継いだ旅程編集とサンプル交通 |
| `lib/screen/base_page.dart` | 起動時復元・3タブ・戻る操作 |
| `lib/data/mock_data.dart` | 北海道10件とサンプル交通。推薦処理はServiceに分離 |
| `pubspec.yaml`, `pubspec.lock` | 保存依存。Chrome保存テスト用にWebアダプターをdev依存へ明示 |
| `ios/Podfile`, `ios/Flutter/{Debug,Release}.xcconfig` | プラグイン導入時にFlutterが生成したiOS設定 |
| `test/*` | 保存・分岐・全画面操作・Chrome実ストレージ検証 |

既存のMaterial 3、HookConsumerWidget / Riverpod、中央最大480pxレイアウト、写真失敗時表示、長押し詳細、ドラッグ並べ替えを活用しています。

## 制限・未実装

- AI・交通API・Firebase・認証・課金は追加していません。
- 条件の保存と引継ぎは実装済みですが、モック観光データに実経路・料金がないため、指定予算・移動上限・徒歩負担・期間を満たすかの判定は行いません。公共交通は距離ではなく時間の上限を指定するUIです。
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
flutter test --platform chrome test/browser_storage_test.dart
flutter build web
```

通常テストではJSON保存層をメモリストアに差し替え、再生成したRepository/Providerからの復元、独立性、書き込み失敗、日付、全24通りの推薦、ホームから旅程までの操作、プロフィールとプリセットCRUDを検証します。Chrome専用テストでは実際のWebアダプターで保存・復元を確認します（通常のVMテストでは1件スキップ）。
