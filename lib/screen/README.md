# 画面の配置

`BasePage`が5タブを並べます。タブの入口は以下の5ファイルです。

| タブ | 入口 | このフォルダに置くもの |
| --- | --- | --- |
| ホーム | `home/home_screen.dart` / `HomeScreen` | ホームの概要画面、写真付きヒーローなど |
| スワイプ | `swipe/swipe_home.dart` / `SwipeHome` | ランダムな観光地を表示するタブ |
| 旅のしおり | `bookmark/bookmark_home.dart` / `BookmarkHome` | 旧ホームのしおり表示、空状態、投稿・チャットの入口 |
| 旅程作成 | `itinerary/itinerary_home.dart` / `ItineraryHome` | 入力、編集、AI作成、地図・交通選択などの部品 |
| プロフィール | `profile/profile_home.dart` / `ProfileHome` | 基本設定、アカウント表示、プリセット管理 |

```text
screen/
├── base_page.dart
├── home/
│   ├── home_screen.dart          # タブの入口・共通フローとの切替
│   ├── home_overview.dart        # 新ホームの表示
│   └── widgets/                 # 写真付きヒーロー
├── swipe/
├── bookmark/
│   ├── bookmark_home.dart       # しおり・交通詳細をタブ内で表示
│   ├── widgets/                 # 代表写真・タイムライン・空状態
│   ├── posts/                   # 投稿一覧・投稿作成
│   └── chat/                    # 会話一覧・チャットルーム
├── itinerary/
│   ├── itinerary_home.dart
│   ├── itinerary_setup_screen.dart
│   ├── itinerary_editor.dart
│   └── widgets/                 # 地図・交通選択・AIパネルなど
├── profile/
│   └── widgets/                 # 設定フォーム・アカウント表示
├── shared/
│   ├── discovery/               # 7つの質問 → AIおすすめ一覧、検索条件の変更
│   │   └── widgets/             # 好奇心の質問・旅行条件の各ページ
│   ├── experiences/             # 観光地一覧・詳細
│   │   └── widgets/             # 一覧カード・PageViewのカード・スワイプ説明
│   ├── trips/                   # 旅行一覧Drawer
│   ├── transport/               # AI交通カード・乗換詳細
│   ├── posts/                   # 詳細画面でも使うレビュー・投稿カード・コメント
│   └── account/                 # プロフィールとチャットで使うログイン・登録画面
└── admin/                       # 管理者用の画面・診断ページ
```

## 依存関係

- タブ専用の画面と部品は、そのタブのフォルダに置きます。小さな部品は`widgets/`へ分けます。
- 複数タブで使う画面・ドメイン共通の部品は`shared/`に置きます。`shared/`から個別タブの実装はimportしません。
- 写真・地図・共通ボタンなどの汎用UIは、従来どおり`lib/widgets/`に置きます。
- 画面遷移の共通操作は`lib/navigation/travel_navigation.dart`です。ホーム以外から質問を始める場合も`beginInterestSearch`を使い、ホーム画面の実装をimportしません。
- データと状態は`lib/state/`、通信は`lib/service/`・`lib/repository/`に置きます。AI作成の要求・結果購読は`ai_trip_state.dart`、ランダムなスワイプ用状態は`swipe_state.dart`です。
- 必要な型は定義元のファイルから直接importします。タブの入口を別画面のexport窓口として使いません。

## 質問・推薦の共通フロー

`beginInterestSearch` → `DiscoveryState`更新 → `HomeScreen`が`shared/discovery/interest_search_flow.dart`を表示します。好奇心の3問と旅行条件の4ページを終えると`recommended_places_list.dart`を表示します。

ホーム・しおりのStep1・旅程編集の検索開始はこの入口を共用します。ランダムなスワイプは独立した状態を使いますが、観光地カードと保存先は共通です。フォルダの移動で保存キー、データ形式、AIの接続先は変更していません。
