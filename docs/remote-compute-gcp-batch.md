# GCP Batch + Spot VM によるリモート計算方針

状態: 試行予定  
採用日: 2026-10-09

この文書は、10枚形・13枚形などの重いレポート生成を Google Cloud Batch の Spot VM で実行するための
現行方針を定める。選定時の背景、比較対象、判断理由は
[remote-compute-platform-rationale-2026-10-09.md](remote-compute-platform-rationale-2026-10-09.md) に残す。

ここに書くCLI、コンテナイメージ、GCPリソースはまだ実装されていない。最初の試行結果に応じて、
具体的なmachine type、リージョン、再試行回数を更新する。

## 目的

- ローカルから1コマンドで計算ジョブを投入できるようにする。
- ローカル端末やIDEの接続状態に依存せず、計算を完了できるようにする。
- Spot VMが中断されたとき、同じジョブを自動的に再試行する。
- 成果物と再開に必要な中間生成物をVMの外に保存する。
- ジョブ終了後は、成功・失敗にかかわらず計算VMを残さない。
- 実行したソース、設定、資源、結果を後から対応付けられるようにする。

## 対象と対象外

対象:

- 10枚形レポート生成。
- 13枚形レポート生成。
- 将来追加する、数十分以上または大容量メモリを必要とするバッチ計算。

対象外:

- 通常の編集、証明、単体テスト、4枚形・7枚形レポート。これらは引き続きローカルまたは
  `development` devcontainerで実行する。
- 対話的なリモート開発環境。必要な場合はdevcontainerやDevPodを別用途として使う。
- 常時稼働サーバー、Web API、複数利用者向け計算サービス。

## 目標とする利用方法

最終的には、GCP固有の操作をラッパーの内側へ隠す。

```bash
./scripts/remote-compute thirteen-tile
```

補助操作は次の形を目標とする。コマンド名と引数は実装時に確定する。

```bash
./scripts/remote-compute thirteen-tile --detach
./scripts/remote-compute status JOB_ID
./scripts/remote-compute logs JOB_ID
./scripts/remote-compute download JOB_ID
```

投入後のジョブ管理はGCP側で行う。`--detach`後にローカル端末を終了しても、ジョブの再試行、
VM削除、ログ保存が継続する構成にする。

## 全体構成

```text
local remote-compute command
  |
  +-- identify source commit and compute image
  +-- submit Google Cloud Batch job
        |
        +-- provision Spot VM
        +-- pull immutable compute image
        +-- download checkpoint if present
        +-- run Lake executable
        +-- upload checkpoint, report, log, and metadata
        +-- delete VM automatically
  |
  +-- optionally wait and download the report
```

使用するGCPサービスを次に限定する。

| サービス | 用途 |
| --- | --- |
| Cloud Batch | ジョブ、Spot VM、再試行、VM削除の管理 |
| Compute Engine | Batchが作成する計算VM |
| Artifact Registry | commitに対応する計算コンテナイメージ |
| Cloud Storage | 中間生成物、最終レポート、メタデータ、補助ログ |
| Cloud Logging | 実行中の標準出力・標準エラー確認 |
| Cloud Build | ローカルでイメージをビルドしない場合の候補 |

初期試行では、プロジェクト、Artifact Registry repository、Cloud Storage bucketを各1個にする。
不要なネットワーク、常設VM、Kubernetes cluster、独自のジョブ管理サーバーは作らない。

## 計算イメージ

既存のdevcontainerと同じLean toolchainを使う計算専用イメージを用意する。開発用の
`.devcontainer/Dockerfile`を直接本番ジョブの入口にはせず、次の性質を持つ別イメージにする。

- ソースと依存関係を含み、起動後に長い環境構築を繰り返さない。
- `lake build`済みの実行ファイルを含む。
- イメージタグだけでなくdigestを実行メタデータへ保存する。
- Git commit SHAをイメージタグへ含め、同じcommitでは再利用する。
- ジョブ種別と実行引数をentrypointへ明示的に渡せる。
- SIGTERMを受けたとき、可能な範囲でログと完了済み中間生成物を退避する。

Mathlib cacheとLake build cacheをコンテナイメージへ含めるかは、イメージサイズと再ビルド時間を
初回試行で測って決める。

## 資源設定

既存のdevcontainer最低要件を初期値にする。

| ジョブ | 初期CPU | 初期メモリ | 初期永続データ容量 |
| --- | ---: | ---: | ---: |
| 10枚形 | 4 vCPU | 4 GB以上 | 32 GB以内を想定 |
| 13枚形 | 16 vCPU | 64 GB以上 | 64 GB以内を想定 |

13枚形の初回試行では、OSとコンテナの余裕を確保するため64 GBちょうどではなく、128 GB級の
machine typeも候補にする。`/usr/bin/time -v`、生成物サイズ、worker別のメモリ使用量を記録し、
実測後に最小構成へ下げる。

現在の13枚形初期パラメーターは次である。

```bash
lake exe thirteen-tile-report-gen \
  --generation-workers=16 \
  --classification-workers=8 \
  --buckets=256
```

分類workerはCPU数へ自動追従させない。分類workerごとにbucket内のHashMapを持つため、worker数を
増やすとメモリ使用量も増える。

リージョンは東京へ固定しない。バッチ計算では対話遅延よりSpot在庫、価格、Artifact Registryと
Cloud Storageの配置を優先する。データ転送料を避けるため、利用するサービスは同じregionへ置く。

## ジョブのライフサイクル

1. ローカルで作業ツリーが実行可能な状態か確認する。
2. Git commit SHAに対応する計算イメージを検索する。
3. イメージがなければビルドし、Artifact Registryへpushする。
4. 一意なJob IDとCloud Storage prefixを作る。
5. Batch job specを生成し、Spot VM、資源量、再試行回数、コンテナdigestを固定する。
6. Batchへ投入する。
7. VM内で中間生成物を復元し、計算を実行する。
8. 中間生成物、レポート、メタデータ、補助ログをCloud Storageへアップロードする。
9. BatchがVMを削除する。
10. 同期実行ならローカルへ最終レポートをダウンロードする。

ジョブ投入後にローカルプロセスが終了しても、手順7から9を完了できるようにする。ローカルの
終了処理にVM削除を依存させない。

## 中断、再試行、チェックポイント

Batchの自動再試行を使い、Spot中断時は新しいVMで同じタスクを再実行する。初期値は最大3回程度とし、
Spot在庫と実測時間を見て調整する。プログラムの入力不正や再現性のある実装エラーを無制限に
再試行しない。

VMのboot diskとlocal SSDは失われる前提にする。再試行で必要なものはCloud Storageへ保存する。

### 10枚形

初期試行ではジョブ全体の再実行を許容する。実行時間または再試行コストが問題になった場合だけ、
より細かいcheckpointを追加する。

### 13枚形

現在の実装は、生成完了後に
`.lake/build/thirteen-tile-buckets/generation.done`を作り、再実行時に生成済みbucketを再利用する。
初期試行では、生成完了後のbucketディレクトリをarchiveしてCloud Storageへ保存し、再試行時に
復元する。

```text
.lake/build/thirteen-tile-buckets/
```

生成途中のcheckpointと分類bucketごとのcheckpointは現在存在しない。そのため初期試行では、

- 生成中断: 生成を最初から再実行する。
- 生成完了後の分類中断: 保存済みbucketを復元し、分類を最初から再実行する。

とする。分類の再実行損失が大きいと実測された場合は、分類結果をbucket単位で永続化し、
Batch Array Jobで未完了bucketだけ再実行する設計へ進む。

## Cloud Storage上の配置

ジョブごとに独立したprefixを使う。

```text
gs://BUCKET/jobs/JOB_ID/
  request.json
  metadata.json
  checkpoints/
    thirteen-tile-buckets.tar.zst
  logs/
    time-v.txt
  results/
    thirteen-tile-direct-report.txt
```

`metadata.json`には少なくとも次を記録する。

- Job IDとBatch Job名。
- Git commit SHAと、dirty treeからの実行を許可したか。
- コンテナイメージ名とdigest。
- Lean toolchain。
- ジョブ種別と完全な引数。
- machine type、vCPU数、メモリ量、region。
- Spot provisioning model。
- 開始時刻、終了時刻、終了コード、再試行回数。
- `/usr/bin/time -v`で取得できる最大RSSなどの資源統計。
- 入力checkpointと出力レポートのchecksum。

成功した最終レポートはリポジトリの既存出力名へダウンロードできるようにする。ただし、
追跡済みファイルを暗黙に上書きせず、上書き前に対象とJob IDを表示する。

## アカウントと権限

単一利用者、単一GCPプロジェクトを初期前提にする。日常操作で個別のservice account keyを
ダウンロードせず、ローカルは`gcloud auth login`とApplication Default Credentials、Batch側は
Google管理または専用service accountを使う。

Batch jobのservice accountには、必要なArtifact Registry imageの取得、対象bucket prefixへの
読み書き、Loggingへの出力だけを許可する。ソースリポジトリの個人credentialやGCPの長期秘密鍵を
コンテナイメージへ含めない。

## コスト制御

- Spot VMだけを初期対象にし、暗黙のオンデマンドfallbackは行わない。
- ジョブに最大実行時間と最大再試行回数を設定する。
- CLIは投入前にmachine type、Spot、region、最大再試行回数を表示する。
- ラベルにrepository、job type、Git commit、Job IDを付ける。
- Artifact RegistryとCloud Storageに保持期間ルールを設定する。
- 失敗ジョブのcheckpointは調査期間だけ残し、期限後に削除する。
- GCP budget alertを設定する。ただしbudget alertは強制停止ではないため、ジョブ側の上限を主とする。
- オンデマンドVMを使う変更は、明示的なCLI optionと確認を必要とする。

## 可観測性と失敗時の扱い

標準出力と標準エラーをCloud Loggingへ送り、計算プログラムは長時間無出力にならないよう進捗を出す。
終了時には成功・失敗を明確に区別し、成果物がない失敗を成功として扱わない。

次を別の状態として表示する。

- Spot中断により再試行待ち。
- Spot在庫不足によりスケジュール待ち。
- アプリケーションが非ゼロ終了。
- 最大再試行回数へ到達。
- 計算成功後の成果物アップロード失敗。
- 計算成功かつ成果物検証成功。

レポートは、アップロード後にchecksumを検証できた場合だけ成功成果物として扱う。

## 導入段階と完了条件

### Phase 1: 10枚形で疎通確認

- GCPリソースのbootstrap手順を作る。
- 計算イメージを作り、commit SHAで再利用できることを確認する。
- Spot VMで10枚形レポートを完走する。
- VMが自動削除されることを確認する。
- ローカル結果と主要件数、checksumを比較する。
- 意図的な中断または失敗で再試行と上限到達を確認する。

### Phase 2: 13枚形の資源測定

- 16 vCPU、128 GB級から開始する。
- bucket生成時間、分類時間、最大RSS、bucket archiveサイズを測る。
- 生成済みbucketをCloud Storageから復元して分類を再開できることを確認する。
- 実測に基づきmachine type、worker数、bucket数を更新する。

### Phase 3: 必要な場合だけ細粒度化

- 分類のSpot中断損失が許容できない場合、bucket別結果を永続化する。
- 独立処理可能な単位が確定した後にBatch Array Jobを導入する。
- 単一ジョブで十分なら、Array Jobや独自schedulerは導入しない。

試行を採用済み運用へ変更する完了条件は次のとおり。

- 10枚形で再現可能な結果を取得できる。
- 成功時と失敗時の両方で計算VMが残らない。
- Spot中断後に人手なしで再試行できる。
- 成果物がVM削除前に永続化され、Job IDから取得できる。
- 予想外のオンデマンド課金へ切り替わらない。
- 実行commit、引数、資源、結果をmetadataから追跡できる。

## 参考資料

- [Google Cloud Batch documentation](https://cloud.google.com/batch/docs)
- [Create and run a basic job](https://cloud.google.com/batch/docs/create-run-basic-job)
- [Automate task retries](https://cloud.google.com/batch/docs/automate-task-retries)
- [Compute Engine Spot VMs](https://cloud.google.com/compute/docs/instances/spot)
- [Artifact Registry documentation](https://cloud.google.com/artifact-registry/docs)
