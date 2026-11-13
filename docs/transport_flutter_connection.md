# Flutter → Firebase Functions → Dify：交通最適化通信

Flutter側の通信実装とモック確認を追加した。旅のしおり画面・TripState・既存観光地マッチング・GTFS生成・Functionsの実装・Difyは今回変更していない。認証・通信は明示呼出し専用で、自動ログイン・再試行・旅程上書きは行わない。

## 確認した既存仕様

- `functions/transport_dify.js`: Callableの入力は `{transport_data: JSON文字列}`、出力は `{success, itinerary: Code ④のオブジェクト全体, message}`。
- Firebase CLIによる読み取り専用のデプロイ一覧で、`optimizeTransportItinerary` が `asia-northeast1`、gcfv2、ACTIVEであることを実確認した。デプロイは行っていない。
- `cloud_functions`、`firebase_auth`は導入済み。RiverpodのProvider・`cloudServicesProvider`を再利用。
- 既存`transportFunctions()`が東京リージョンとFunctions emulator設定を管理するため、新サービスでも利用する。
- 既存準備用`transportOptimizerProvider`は入力条件から`prepareTransportOptimization`を呼び、`PreparedTransportOptimization.transportJson`を返す。フィールド名transport_jsonを新Callableのtransport_dataへマッピングする。生成/軽量化は重複実装しない。
- 既存AIマッチングは未ログインで匿名認証するが、新通信サービスではその動作を流用せず、currentUserが無ければunauthenticatedで停止する。既存の匿名認証済みユーザーはバックエンド同様に利用できる。

## 追加ファイル

- `lib/service/transport/transport_itinerary_service.dart`: Riverpod Provider、認証確認、既存Callable factory利用、130秒タイムアウト、注入可能な通信、エラー変換。
- `lib/model/optimized_transport_itinerary.dart`: Code ④の結果モデル。従来のcandidates/selectedCandidateIdモデルは互換性のため変更せず、別クラスにした。
- `test/transport_itinerary_service_test.dart`: 実軽量サンプルを入力に使うモック6件。
- `test/transport_itinerary_live_browser_test.dart`: 実FlutterFire Web SDKで1回だけ呼ぶ任意のブラウザテスト。既定ではskip。
- `tool/serve_transport_test_fixture.py`: テストへ対象JSONだけを提供するlocalhost限定サーバー。
- 本書。

## 呼出し方

```dart
final service = ref.read(transportItineraryServiceProvider);
final response = await service.optimize(lightweightNetworkJson);
final itinerary = response.itinerary;

// 既存準備結果がある場合（追加の生成・再エンコードなし）
final response2 = await service.optimizePrepared(prepared);
```

Callable名はoptimizeTransportItinerary、リージョンはasia-northeast1。cloud_functions SDKが現在のFirebase Authトークンを付加する。呼出しは1回、再試行ループなし。未ログインなら`TransportItineraryException(code: 'unauthenticated')`。

文字列を二重にjsonEncodeしない。Flutterからキー・UID・Difyヘッダーは送らない。クライアントでrawサイズ4,000,000 UTF-16 units/Unicode文字以下・4,000,000 UTF-8 bytes以下（2026-11-13時点の上限）、schemaVersionとネットワーク配列を確認し、詳細な参照・形式検証は既存Functionsへ委ねる。入力原文・例外details・巨大JSONをログ出力しない。

## 結果モデル

`TransportItineraryResponse`は`itinerary`と`message`を保持。success=falseはworkflow-failed例外であり、既存旅程へ適用しない。

`OptimizedTransportItinerary`はstatus、candidateId、summary、visits、legs、steps、requiresReview、reviewReasonsを保持する。summaryにはdepartureSeconds/arrivalSeconds/transferCount/walkingSecondsのnullable getter、legsには時刻とsteps getterを用意した。visitsのspotId/placeId/idからvisitOrderを取り出せる。日時表現やフィールド名を推測して新しい時刻・移動時間を生成しない。

元JSON全体は`data`/`toJson()`に再帰的にコピー・読取専用で保持する。未知の将来フィールド、root.steps、各leg.steps、review理由の文字列/構造化オブジェクトも削除しない。requiresReview欠落はfalseにせずnull。モデルを外部から編集して元データや保存済み旅程を変えることはできない。

現時点では本番Code ④の全フィールド構成が未確認のため、getterに無いフィールドはdataから取得できるようにしている。旧候補モデルへ強制変換しない。

## エラー

`TransportItineraryException`のcodeでunauthenticated、permission-denied、deadline-exceeded、resource-exhausted、failed-precondition、invalid-argument、internal、unavailableを区別する。success=falseはworkflow-failed、壊れた応答はinvalid-response。表示用messageはサービス内の固定文言にし、任意の上流エラー本文を転送しない。130秒のクライアントtimeoutはFunctions120秒/Dify90秒より長い。タイムアウト後にサーバー側の処理が続く場合があるため、自動再試行はしない。

## テスト結果

- 新規モック6件成功。実軽量サンプルの文字列がtransport_dataとして1回送られること、Riverpod経由、訪問順・時刻・乗換回数・徒歩時間、全JSON・steps・review保持を確認。
- 認証なしで呼出しなし、不正/過大入力、success=false、不正応答、Functions各エラー、timeout、再試行なし、immutableなコピーを確認。
- 既存準備/交通journey/旅程時刻表を合わせた13件成功。
- 新規Dart4ファイルのflutter analyzeは指摘なし。
- AIマッチングの既存テストでは4件中3件成功・UI1件失敗。`test/ai_matching_integration_test.dart:100`が「あなたに合う体験を探しています…」との完全一致を期待する一方、現在のexperience_deck.dartは同文＋改行「もう少しで完了します…」を表示する。対象コードに今回の変更はなく、スコープ外の既存UI/テストは修正していない。

実Firebase→Dify→Flutter通信は**未実行**。デプロイ一覧の確認には成功したが、実通信テストの起動が自動承認レビューで拒否された。理由は、約35万文字のローカル交通データを外部Difyへ送ること、テスト用匿名認証の作成と課金対象の呼出しについて明示承認が不足しているため。実通信成功とは報告しない。回避実行・Secret取得・別経路での送信はしていない。

## 承認後の実通信テスト手順

このテストは新しいブラウザセッションの匿名認証を明示的に作り、完了時にテスト用ユーザーを削除してsignOutする。本番サービスの認証動作は変更しない。既存サンプル（2026-11-01、札幌→メロード→博物館→札幌、352,129 bytes）のみを送る。Difyへの呼出しは最大1回であり、失敗時にも再試行しない。通常のDify/LLM利用料が発生し得る。

別ターミナルで `python3 tool/serve_transport_test_fixture.py` を起動し、以下を実行する。

```sh
flutter test --platform chrome \
  --dart-define=TRANSPORT_LIVE_TEST=true \
  --dart-define=TRANSPORT_NETWORK_URL=http://127.0.0.1:8766/network.json \
  test/transport_itinerary_live_browser_test.dart
```

終わったらサーバーをCtrl-Cで停止する。Firebase Auth匿名認証とブラウザからのCallableが利用可能であることが必要。App Check強制が有効な環境では既存の適切なテスト端末設定が必要であり、強制設定を解除して回避しない。

## 次の画面連携

1. 現在のログイン済みユーザーと選択地点に対応する入力を、既存GTFS準備/軽量化処理で生成する。
2. 明示操作で新Providerを呼び、読み込み・安全なエラー・結果確認の状態を表示する。
3. 実Code ④の結果形状を確認したうえでTripState/TransportSelectionへの変換アダプターを実装する。全legs/steps、review情報、運行日・秒単位時刻を保持する。
4. ユーザー確認前や失敗時に既存旅程を上書きせず、入力変更後に遅れて返る結果を破棄する仕組みを追加する。

これらUI/保存状態の接続は今回実施していない。
