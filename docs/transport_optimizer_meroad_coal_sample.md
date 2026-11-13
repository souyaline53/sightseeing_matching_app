# 札幌駅 → メロード → 夕張市石炭博物館 → 札幌駅：探索入力

入力本体は [transport_optimizer_meroad_coal_network.json](transport_optimizer_meroad_coal_network.json)。既存schemaVersion: 1と同じ、最適化前のネットワークJSON。ファイル全体をDifyの文字列入力transport_jsonに渡す。status/candidates/legs/selectedCandidateIdなどの解答は含めない。以前の1観光地サンプルは変更していない。

旅行日はユーザー指定の変更に従い **2026-11-01（日）**。08:30出発可能・17:00札幌帰着期限、メロード60分・博物館90分。placesにmelon、coalの順で入力するが、既存policyのevaluateAllVisitPermutations=trueは維持しており、探索側で訪問順の両順列を評価できる。指定されたメロード→博物館の順でも成立することを別テストで確認した。

## 本番抽出

Firestoreのtransport_feeds公開版メタデータと、参照先Storageのchecksum検証済みGTFS検索用ファイル、手動乗換マスター、sightseeing_spot/melon・coalを読取り専用で取得した。便・運行日・秒単位時刻・乗降可否・順序は登録GTFSから抽出する。Firestore、Storage、アプリの処理は変更していない。

| 項目 | 件数 |
| --- | --- |
| stops | 99 |
| routes | 8 |
| agencies | 2 |
| instances | 192 |
| segments | 1,463 |
| transfers | 2 |
| コンパクトJSON本体 | 462,533 bytes（末尾改行込み462,534 bytes） |

500,000 bytes以下にするため、対象地域を札幌〜新夕張のJR17駅と、新夕張駅前・石炭博物館に接続する夕鉄バスに限定した。JRの対象駅名一覧はスクリプトのrailNamesに明示する。対象外の小樽・帯広・室蘭方面の区間は除外する。対象便の時刻表から実在の隣接区間を生成した後に地域で絞るため、除外駅を飛び越える架空区間は作らない。地域内の途中停留所・両方向の便・代替便を時刻窓内で保持し、先頭N件だけに切り捨てる処理はない。全北海道の別ルートを含む最適性は保証しない。

transfersには新夕張JR駅↔新夕張駅前の両方向・各300秒を保持する。元のunverified状態やnote、sourceUrlも保持する。条件付き・禁止・未対応規則も対象停留所間に登録されていれば削除しない。

## 開館・徒歩情報のサンプル補完

- [博物館公式](https://www.coal-yubari.jp/info/)では2026年は4月18日〜11月3日に開館、10〜11月は10:00〜16:00（最終入場15:30）。11月1日は日曜日で通常開館期間内。90分滞在を閉館までに完了する条件なら入館は遅くとも14:30となり、最終入場条件も満たす。
- [冬期休館案内](https://www.coal-yubari.jp/)では11月4日から冬期休館。以前の11月13日のまま入館可能とするサンプルにはしていない。
- [夕張市メロード案内](https://www.city.yubari.lg.jp/site/kanko/1197.html)の11月営業時間10:00〜18:00を使用する。11月2日は月曜定休なので、変更候補日には採用していない。
- 博物館の本番登録はバス停から徒歩1分・100m・unverifiedだが、[博物館公式の公共交通案内](https://coal-yubari.jp/file/timetable202505n.pdf)はバス停から本館まで約500mとしている。サンプルでは本館への移動に片道10分の計画余裕を採用する。直線距離で接続を推定したものではなく、公式に案内された徒歩接続に時間余裕を設定したもの。実測所要時間ではない。
- メロードは新夕張JR駅から5分、新夕張駅前バス停から3分を採用（既存登録時間）。接続経路は夕張市のJR・バス停からの公式アクセス案内で補完し、サンプル内で使用可にする。
- 札幌駅の出発・到着はJR乗降地点として0秒で接続する。駅入口や現在地からホームまでの移動は含めない。
- これら営業時間・徒歩接続確認はサンプル内だけの補完であり、本番データの未確認状態は更新していない。JSONのestimated=falseは直線距離による未確認接続ではないという扱いで、現地実測・当日の運行や通行・空席の保証ではない。

## 成立検証

`functions/transport_optimizer_coal_sample.test.js` では入力JSONの実便・連続区間を参照して、次の接続が成立することを検証した。選択結果はネットワークJSONへ埋め込んでいない。

1. 08:52札幌 → 10:02新夕張 → 徒歩5分 → メロード10:07〜11:07。
2. 徒歩3分 → 11:28新夕張駅前 → 12:15石炭博物館バス停。
3. 徒歩10分 → 本館12:25〜13:55 → 徒歩10分 → 14:35復路バス。
4. 15:22新夕張駅前 → 登録済み300秒の乗換移動 → 15:36新夕張 → 16:40札幌。

営業時間内滞在、乗降可否、同一便の連続sequence、徒歩時間、乗換余裕、17:00期限を確認する。Difyでの最適化結果ではなく、登録時刻表とサンプル補完条件での実行可能性の確認である。実運行・予約・運賃は未確認。

## 関連ファイル

- [抽出条件](transport_optimizer_meroad_coal_request.json)
- [件数・出典・公開版](transport_optimizer_meroad_coal_extraction.json)
- `tool/meroad_coal_transport_sample.cjs`: `node tool/meroad_coal_transport_sample.cjs`で本番から読取り専用再生成。
- オフライン再生成: `node tool/meroad_coal_transport_sample.cjs --snapshot /path/network.json /path/spot_records.json`。
- 検証: `node --test functions/transport_optimizer_coal_sample.test.js functions/transport_optimizer_sample.test.js functions/transport_optimizer.test.js`（11件成功）。

既存v1形式を維持するが、Code ②のPython本体は未共有のため、そのコードとの実行互換性は未検証。
