# Dify Codeノードへ渡す最適化前の交通ネットワーク

使用するファイルは **[transport_optimizer_sample.json](transport_optimizer_sample.json)**。
`schemaVersion: 1` のネットワーク入力そのものであり、`status`、`candidates`、`legs`、`selectedCandidateId`、訪問順序や選択済みの往復便は含まない。

2026年11月13日（金）の「札幌駅 → 道の駅メロード → 札幌駅」を対象に、Firestoreの公開版メタデータが参照するStorageのGTFS検索用データを読み取り、運行日・時間帯・対象接続で抽出した。本番Firestore・Storageの書込み、アプリの変更、デプロイは行っていない。

| 入力条件 | 値 |
| --- | --- |
| 旅行日 | 2026-11-13、Asia/Tokyo |
| 出発可能時刻 | 10:30（37800秒） |
| 最終到着期限 | 14:30（52200秒） |
| 出発地・到着地 | 札幌駅のJR乗車・降車地点 |
| 訪問地 | 道の駅メロード（既存ID: melon） |
| 滞在時間 | 60分（3600秒） |
| 営業時間 | 10:00〜18:00（36000〜64800秒、サンプル補完） |
| 交通手段 | 鉄道・バス・徒歩 |
| 優先条件 | 乗換回数 |
| 最低乗換余裕 | 300秒 |

## 抽出内容・容量

- stops: **141**、routes: **8**、agencies: **2**。
- instances: **103**、segments: **920**、transfers: **2**。
- JSON本体: **295,001 bytes**。ファイルは改行1 byteを加えたコンパクトJSONで保存し、コピーする実ファイルも500,000 bytes以内に収めた。
- schemaVersion、workflow、date、timezone、timeUnit、departureSeconds、deadlineSeconds、modes、preference、minimumTransferSeconds、policy、places、stops、routes、agencies、instances、segments、transfers、versions、warningsという既存v1構造を維持する。
- instancesの実運行日、segmentsの秒単位時刻・停車順序・乗降可否・同一便IDを保持する。前日運行日の24時超便も既存抽出ロジックで判定する。
- 往路・復路とも複数の直通便を含み、普通列車・快速・特急・夕鉄バスの候補区間を渡す。どの便を選ぶか、どこで乗り換えるか、実行可能な旅程があるかはCodeノードで計算する。

抽出対象は以下の接続範囲。停留所の座標で便の途中区間を切り落とす方式ではない。

1. JR北海道の、札幌・新札幌・南千歳・追分・新夕張のいずれかに停車する便。
2. 夕鉄バスの、新夕張駅前に停車する便。
3. 上記便について、指定日に運行し、10:30〜14:30内に完結する全隣接区間と全中間停留所。
4. 出力停留所間の登録済み乗換ルールを全件保持する。

北海道全域・中央バス等を含む全交通網からの最適解は保証しない。上記範囲外の別系統を経由する代替経路は今回の対象外。対象便の途中停留所は地域外でも保持する。対象地域・時間窓を広げる場合は抽出条件を明示的に変更し、容量超過時はエラーとする。件数上限で便を黙って切り捨てない。

## transfersは探索コードの対応状況によらず保持

今回の実登録には次の2件があり、両方を出力した。

- 新夕張JR駅 → 新夕張駅前バス停: transferType=2、minTransferSeconds=300。
- 新夕張駅前バス停 → 新夕張JR駅: transferType=2、minTransferSeconds=300。

元のid、direction、type、必要時間、sourceType、verificationStatus、name、note、sourceUrlを保持する。管理用createdAt/updatedAtだけを除く。便・路線条件付きルールがあればfrom/toTripId・from/toRouteIdも保持する。type 3/4/5などが登録されていればusableForRouting=falseでも削除しない。今回の実データに存在しないルールを架空で追加しない。

verificationStatusは元のunverifiedのまま。usableForRoutingは既存v1の時間・type条件による派生フラグであり、現地確認済みを意味しない。Code側では禁止ルール・条件の優先順位・移動時間を評価する必要がある。未対応ルールを無条件の接続へ変換してはならない。既存policyはtype 3/4/5を禁止とする保守的な設定で、4/5の車内継続仕様は未対応。

## 地点情報の出典と補完

交通便・時刻・乗換データは実登録データから抽出。地点入力には以下の明示的なサンプル前提がある。

- 札幌駅は駅入口やユーザーの現在地ではなく、JR乗車・降車地点として定義する。対応するJR stopへの接続は0秒。駅入口からホームまでの歩行時間は含めない。
- 本番メロードの営業時間はunknownだったため、前回確認した[夕張市公式案内](https://www.city.yubari.lg.jp/site/kanko/1197.html)の11月営業時間10:00〜18:00をサンプル入力だけに補完する。11月13日は同案内の月曜定休・11月18日等の特別休業日に該当しない。臨時休業は別途確認が必要。
- メロード↔新夕張JR駅は既存登録の徒歩5分を採用。前回確認した同公式案内の徒歩1分・約100mという接続根拠に、余裕を持つ登録時間を組み合わせ、サンプルのみ使用可とする。Firestoreの未確認フラグは更新しない。
- メロード↔新夕張駅前バス停は既存登録の徒歩3分・unverifiedを維持し、usableForRouting=falseとして出力する。Code側で未確認接続を確定扱いしない。

この補完と本番の登録値そのままの状態を区別すること。運賃・空席・リアルタイム運休・徒歩道路形状は含まない。

## Difyへの渡し方とCode ②の互換性

ファイル全体をUTF-8で読み、Dify開始ノードの文字列変数 `transport_json` に設定する。Python Codeノードで文字列を受け取る場合は `json.loads(transport_json)` でオブジェクトへ戻す。すでにオブジェクトとして受け渡す場合は再度JSONデコードしない。

既存schemaVersion: 1のフィールド名と型を維持した。「以前のCode ②」のPython本体はリポジトリに見当たらないため、その実コードとの実行互換性までは検証できていない。transfersを読み取らないコードの場合もJSONには規則を残してあり、Code側での対応が必要。未対応規則がある状態で現実の乗換可否を保証しない。

## 関連ファイル・再生成

- [transport_optimizer_meroad_request.json](transport_optimizer_meroad_request.json): 抽出に使用する地点・時間条件。Difyへ渡すネットワーク本体とは別。
- [transport_optimizer_meroad_extraction.json](transport_optimizer_meroad_extraction.json): 件数・バイト数・対象範囲・元の公開versionId。旅程候補は含まない。
- `tool/meroad_transport_sample.cjs`: 入力ネットワークだけを生成する。往復便を固定した参照旅程の生成処理は取り除いた。
- `transport_optimizer_meroad_expected.json` は前回作成した出力参照例であり、今回の入力には使わない。新しいスクリプトも生成・更新しない。

本番から再抽出: リポジトリルートで `node tool/meroad_transport_sample.cjs`。既存Firebase認証と読取権限が必要。Firestore公開版・manual revisionとchecksum検証済みGTFSを取得し、上記入力JSON・request・extractionの3ファイルだけをローカルに書く。

オフライン再抽出: `node tool/meroad_transport_sample.cjs --snapshot /path/network.json`。スナップショット自体はコミットしない。

検証: `node --test functions/transport_optimizer_sample.test.js functions/transport_optimizer.test.js`。9件成功。schema v1、解答フィールド不在、往復の複数便、参照整合性、時間窓・容量、実登録2方向transfer保持、未対応/便条件付きルールの保持、範囲外の中間停留所保持を検証した。Code ②・Difyでの実行は未実施。
