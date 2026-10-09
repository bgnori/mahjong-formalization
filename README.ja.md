# Mahjong Formalization

麻雀の数理を Lean 4 で形式化し、計算によって研究するリポジトリです。牌、牌姿、通常形の待ちの意味論、待ち核、既約分類などを、機械検証された仕様と全列挙レポートとして扱います。

[English version](README.md)

## 目的

- 麻雀の構造と待ちの意味論を、型と証明によって厳密に形式化する。
- 全列挙計算により、麻雀の待ちを調査・分類する。
- `example ... := by native_decide` などを使い、例を実行可能な仕様として残す。
- 実装、仕様、証明、ドキュメントをできるだけ同じ場所で育てる。

## 構成

```text
.
├── Mahjong.lean           # ライブラリ全体の入口
├── Mahjong/               # 麻雀の形式化
│   ├── Basic.lean
│   ├── Pattern.lean
│   ├── Hand.lean
│   ├── WaitCompletion.lean
│   ├── WaitCompletionFinder.lean
│   ├── WaitDecompositionCode.lean
│   ├── DirectWaitGeneration.lean
│   ├── Tenpai.lean
│   └── README.md
├── MahjongTests/         # 計算量の大きい回帰テスト
├── MahjongComputations/  # 全列挙と集計レポート
├── docs/                 # 読書順、Lean語彙、プロジェクト語彙
└── reports/              # 生成済みレポート
```

## ビルド

全体を確認する場合:

```bash
lake build
```

麻雀モジュールを明示的に確認する場合:

```bash
lake build Mahjong
```

計算量の大きい回帰テストと全列挙を明示的に確認する場合:

```bash
lake build MahjongTests
lake build MahjongComputations
```

4枚形・7枚形のレポートを生成する場合:

```bash
lake build fourTileReport
lake build sevenTileReport
```

出力先はそれぞれ `reports/four-tile-direct-report.txt` と `reports/seven-tile-report.txt` です。

### GCP Batchでの試行

GCP Batch + Spot VMの環境疎通には、まず4枚形レポートを使う。並列動作の確認には
7枚形レポートを使う。GCPリソースの準備は
[GCP Batch運用方針](docs/remote-compute-gcp-batch.md)を参照する。

```bash
./scripts/remote-compute run four-tile      # 2 vCPU、疎通確認
./scripts/remote-compute run seven-tile     # 8 vCPU、分類フェーズを並列実行
./scripts/remote-compute run ten-tile       # 4 vCPU、10枚形レポート
./scripts/remote-compute run thirteen-tile  # 32 vCPU、数時間、checkpoint付き
```

ジョブ種別ごとにマシンサイズが決まっており、`--workers`の既定値はそのvCPU数になる。
`--detach`を指定すると完了を待たずに投入できる。`status JOB_ID`で状態を確認し、
`download JOB_ID`で成功レポートを取得する。既存ファイルは上書きしない。

10枚形と13枚形は、外部bucketとbucketごとの分類結果をCloud Storageへ同期する。Spot中断後は
最後のcheckpointから再開し、最初からやり直さない。`--fresh`を付けると保存済みcheckpointを
破棄して再計算する。再開した実行の`waitCoreCache*`の値は通し実行と必ず異なる。
wait-coreキャッシュはプロセス内にしか存在しないためで、レポートのそれ以外の行は一致する。

7枚形レポートは末尾に`calculationElapsedMs`を出力するため、実行ごとに内容が変わる。
`reports/seven-tile-report.txt`と比較する際はこの行を除外する。

### 用途別devcontainer

devcontainerは、生成する内容に応じて次の3構成から選択する。

| 構成 | 用途 | ホスト最低要件 |
| --- | --- | --- |
| `development` | 通常の編集・証明・テスト、4枚形・7枚形レポート | 指定なし |
| `ten-tile` | 10枚形レポート | 4 CPU、4 GB RAM、32 GB storage |
| `thirteen-tile` | 13枚形レポート | 16 CPU、64 GB RAM、64 GB storage |

VS Codeでコンテナを開くとき、またはCodespaceの作成オプションで、使用するdevcontainer構成を
選択する。通常のローカル作業では`development`を使い、重いレポートを生成するときだけ対応する
構成を使う。

`hostRequirements`はCodespacesなどが適切なホストを選ぶための最低要件であり、Dockerの資源上限
ではない。どの構成もDockerの`--cpus`・`--memory`制限を設定していない。Codespace作成後は次を
確認する。

```bash
nproc
cat /sys/fs/cgroup/memory.max
df -h /workspaces
```

devcontainer設定を変更した既存Codespaceでは、使用する構成を選び直してコンテナを再作成する。
長時間計算は`tmux`内で起動し、GitHubのCodespaces設定でidle timeoutを最大の240分へ変更する。
terminal出力もidle timeoutをリセットするため、数時間無出力になる計算には定期的な進捗表示を持たせる。

10枚形レポートの実測済み構成は4 workerである。

```bash
lake exe ten-tile-report-gen --workers=4
```

CPU数をそのまま分類worker数にしない。外部bucket生成は多くのcoreを使えるが、分類はworkerごとに
bucket内HashMapを保持するためメモリ使用量も増える。13枚形は生成worker、分類worker、bucket数を
分けて指定できる。16-core Codespaceでの初回候補は次の通り。

```bash
lake exe thirteen-tile-report-gen --generation-workers=16 --classification-workers=8 --buckets=256
```

組織ポリシー上32-core machineを選択できる場合は、生成worker数を32へ増やせる。

生成完了後は`.lake/build/thirteen-tile-buckets/generation.done`が作られる。分類中に停止した場合、
同じ設定で再実行すると既存bucketを再利用して分類から再開する。cacheの永続化やbucketごとの
checkpointは行わない。生成からやり直す場合は`.lake/build/thirteen-tile-buckets`を削除する。

単一ファイルを直接確認する場合:

```bash
lake env lean Mahjong/WaitCompletionFinder.lean
```

## Python分類サンプル

外部利用向けに、Python標準ライブラリだけで動く
`examples/irreducible_wait_classifier.py`を用意している。4・7・10・13枚の牌姿を重複のない
Tenhou 136 ID列で受け取り、`waitDecompositionCodes`を計算する。さらに、待ち核集合を保つ完成面子を
再帰的に除去し、既約分類の固定グローバル整数IDを返す。各IDを`id // 4`で牌種へ正規化するため、
赤5と通常の5は区別しない。

```python
from irreducible_wait_classifier import classify_irreducible_wait

classification_id = classify_irreducible_wait([0, 4, 5, 8])  # 1223m -> 5
```

実行時は`examples`をモジュール検索パスへ加える。非聴牌や不正入力は
`WaitClassificationError`の派生例外になる。

```bash
PYTHONPATH=examples python3 -m unittest discover -s examples -p 'test_*.py'
```

## ドキュメント

読者向け:

- [docs/introduction.md](docs/introduction.md): Lean4と証明付きプログラムが今回の用途で何を支えるか。
- [docs/reading-order.md](docs/reading-order.md): Lean未経験者向けの読む順番。
- [docs/lean-vocabulary.md](docs/lean-vocabulary.md): `namespace`、`theorem`、`cases`、`simp` などの初出説明。
- [docs/domain-vocabulary.md](docs/domain-vocabulary.md): 待ち核、可約、既約など、このプロジェクト内の説明語彙。
- [docs/seven-tile-prior-work-comparison.md](docs/seven-tile-prior-work-comparison.md): 1・4・7枚形について、既存のT001〜T026と本リポジトリの分類を全件対照。

作成・保守側の方針:

- [docs/documentation-policy.md](docs/documentation-policy.md): 読者向け文書、語彙ページ、保守用文書の役割分担。
- [docs/proof-comment-policy.md](docs/proof-comment-policy.md): 定義・定理コメントに書くことと、語彙ページへ逃がすことの切り分け。
- [docs/review-backlog.md](docs/review-backlog.md): ドキュメント整備後に検討する設計・命名課題。
- [docs/wait-decomposition-classification-key-2026-09-13.md](docs/wait-decomposition-classification-key-2026-09-13.md): 待ち分解分類を64 bitキーへ収める設計。
- [docs/remote-compute-gcp-batch.md](docs/remote-compute-gcp-batch.md): GCP Batch + Spot VMによるリモート計算の現行方針。
- [docs/remote-compute-platform-rationale-2026-10-09.md](docs/remote-compute-platform-rationale-2026-10-09.md):
  リモート計算基盤としてGCP Batch + Spot VMの試行を選んだ経緯と見直し条件。

麻雀モジュール単位の概要は [Mahjong/README.md](Mahjong/README.md) を参照してください。

## 来歴

このリポジトリは、Lean 4 の学習環境として
[chantakan/lean4-devcontainer-template](https://github.com/chantakan/lean4-devcontainer-template)
を fork したことから始まりました。その来歴は commit 履歴に保存したまま、現在は独立した麻雀の
形式化・計算研究プロジェクトとして開発しています。
