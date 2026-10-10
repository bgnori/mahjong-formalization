# GCP Batch + Spot VM によるリモート計算方針

状態: 4枚形・7枚形・10枚形・13枚形のGCP Batch実行確認済み
採用日: 2026-10-09

この文書は、10枚形・13枚形などの重いレポート生成を Google Cloud Batch の Spot VM で実行するための
現行方針を定める。選定時の背景、比較対象、判断理由は
[remote-compute-platform-rationale-2026-10-09.md](remote-compute-platform-rationale-2026-10-09.md) に残す。

疎通用のCLIと計算コンテナは実装済み。4枚形レポートはSpot VM上で完走しローカル結果と
バイト単位で一致することを確認済み。7枚形レポートも`e2-standard-8`のSpot VMで完走し、
CPU使用率193%で並列動作することを確認済み。10枚形も4 vCPUのSpot VMで完走し、
ローカル結果との一致を確認済み。10枚形と13枚形はbucket単位のcheckpointをCloud Storageへ
同期して中断から再開できる。13枚形も`n2-standard-32`のSpot VMで7時間11分かけて完走し、
ローカル結果との一致を確認済み。
実測結果に応じて、machine type、リージョン、再試行回数を更新する。

## 目的

- ローカルから1コマンドで計算ジョブを投入できるようにする。
- ローカル端末やIDEの接続状態に依存せず、計算を完了できるようにする。
- Spot VMが中断されたとき、同じジョブを自動的に再試行する。
- 成果物と再開に必要な中間生成物をVMの外に保存する。
- ジョブ終了後は、成功・失敗にかかわらず計算VMを残さない。
- 実行したソース、設定、資源、結果を後から対応付けられるようにする。

## 対象と対象外

対象:

- 初回の環境疎通確認としての4枚形レポート生成。
- 並列動作確認としての7枚形レポート生成。
- 10枚形レポート生成。
- 13枚形レポート生成。
- 将来追加する、数十分以上または大容量メモリを必要とするバッチ計算。

対象外:

- 通常の編集、証明、単体テスト。これらは引き続きローカルまたは
  `development` devcontainerで実行する。4枚形はBatch疎通試行、7枚形は並列動作確認に限り
  対象とする。
- 対話的なリモート開発環境。必要な場合はdevcontainerやDevPodを別用途として使う。
- 常時稼働サーバー、Web API、複数利用者向け計算サービス。

## 目標とする利用方法

最終的には、GCP固有の操作をラッパーの内側へ隠す。

```bash
./scripts/remote-compute run four-tile
```

初回試行では`run`、`status`、`download`を提供する。

```bash
./scripts/remote-compute run four-tile --detach
./scripts/remote-compute status JOB_ID
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
| Cloud Build | 計算イメージのビルド |

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
- 中断時はBatchの再試行に任せる。4枚形・7枚形ジョブに再開用checkpointはない。

`remote-compute.Dockerfile`は4枚形と7枚形のレポート生成器をビルドし、Cloud BuildからArtifact
Registryへpushする。Batch workerはApplication Default Credentialsを使ってレポート、`/usr/bin/time -v`
の計測値、実行metadataをCloud Storageへ保存する。再開用checkpointがないため、中断時は
レポート全体を再実行する。

## 初回試行の準備と実行

必要なローカルツールはGit、Python 3、Google Cloud CLI。GCP project内でBatch、Compute Engine、
Artifact Registry、Cloud Build、Cloud Storage、Cloud Logging APIを有効にする。Artifact Registry
repositoryとCloud Storage bucketは同じregionに作成する。Batch service accountには、対象repository
の`roles/artifactregistry.reader`、対象bucketの`roles/storage.objectAdmin`、projectの
`roles/logging.logWriter`と`roles/batch.agentReporter`を付与する。`batch.agentReporter`がないと、
VM上のBatch agentが状態を報告できず、ジョブが`SCHEDULED`のまま進まない。操作する利用者には
Cloud Build/Artifact Registryへのpush権限、
Batch jobの作成権限、およびBatch service accountの`iam.serviceAccountUser`権限が必要。
Cloud Buildのbuild identityにも対象repositoryへのpush権限を付与する。

設定する環境変数:

```bash
export GCP_PROJECT="your-project-id"
export GCP_REGION="us-central1"
export GCP_ARTIFACT_REPOSITORY="mahjong-compute"
export GCP_BUCKET="your-unique-bucket-name"
export GCP_BATCH_SERVICE_ACCOUNT="mahjong-batch@your-project-id.iam.gserviceaccount.com"
```

初回だけ必要なrepository、bucket、service accountは、存在しない場合に作成する。

```bash
gcloud services enable batch.googleapis.com compute.googleapis.com \
  artifactregistry.googleapis.com cloudbuild.googleapis.com \
  storage.googleapis.com logging.googleapis.com --project="$GCP_PROJECT"
gcloud artifacts repositories create "$GCP_ARTIFACT_REPOSITORY" \
  --repository-format=docker --location="$GCP_REGION" --project="$GCP_PROJECT"
gcloud storage buckets create "gs://$GCP_BUCKET" \
  --location="$GCP_REGION" --uniform-bucket-level-access --project="$GCP_PROJECT"
gcloud iam service-accounts create mahjong-batch --project="$GCP_PROJECT"
```

service accountへ実行に必要な権限を付ける。Artifact Registryへのpush権限はCloud Buildのbuild
identityにも必要である。

```bash
gcloud artifacts repositories add-iam-policy-binding "$GCP_ARTIFACT_REPOSITORY" \
  --location="$GCP_REGION" --project="$GCP_PROJECT" \
  --member="serviceAccount:$GCP_BATCH_SERVICE_ACCOUNT" \
  --role=roles/artifactregistry.reader
gcloud storage buckets add-iam-policy-binding "gs://$GCP_BUCKET" \
  --member="serviceAccount:$GCP_BATCH_SERVICE_ACCOUNT" \
  --role=roles/storage.objectAdmin
gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
  --member="serviceAccount:$GCP_BATCH_SERVICE_ACCOUNT" \
  --role=roles/logging.logWriter
gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
  --member="serviceAccount:$GCP_BATCH_SERVICE_ACCOUNT" \
  --role=roles/batch.agentReporter
```

作業ツリーをcommitした状態で投入する。commit SHAをコンテナtagとmetadataへ記録するため、
dirty worktreeからの投入は拒否する。

```bash
./scripts/remote-compute run four-tile
./scripts/remote-compute run seven-tile
./scripts/remote-compute run ten-tile
./scripts/remote-compute run thirteen-tile
```

既定では完了まで待ち、検証済みレポートを
`reports/JOB_TYPE-batch-JOB_ID.txt`へ保存する。端末を閉じてもよい非同期投入では次を使い、
表示されたJob IDを後で確認・取得する。

```bash
./scripts/remote-compute run four-tile --detach
./scripts/remote-compute status JOB_ID
./scripts/remote-compute download JOB_ID
```

4枚形は`e2-standard-2`、7枚形は`e2-standard-8`、10枚形は`e2-standard-4`、13枚形は`n2-standard-32`で実行する。
いずれもSpot限定、最大3回再試行。最大実行時間はジョブ種別ごとで、4〜10枚形は2時間、13枚形は14時間。
`--workers`の既定値はそのマシンのvCPU数で、`--workers=N`で上書きできる。13枚形では`--workers`が
生成workerの数になり、分類workerはその半数になる。Artifact
Registryに同じ
commit SHAのイメージがあればdigestを再利用し、Batch jobにはtagでなくdigestを渡す。成果物は
`gs://BUCKET/jobs/JOB_ID/`以下に保存する。download時は成功metadataとSHA-256を照合し、既存または
追跡済みのローカルファイルを上書きしない。Spot中断を含む実際の再試行、課金、VM自動削除は、
GCP上での初回試行後に確認する。

7枚形レポートは`calculationElapsedMs`を含むため、実行ごとに内容が変わる。
`reports/seven-tile-report.json`との比較では、この項目を除外する。

```bash
python -c 'import json,sys; d=json.load(open(sys.argv[1])); d.pop("calculationElapsedMs",None); print(json.dumps(d,sort_keys=True))' \
  reports/seven-tile-report.json > /tmp/seven-local.json
python -c 'import json,sys; d=json.load(open(sys.argv[1])); d.pop("calculationElapsedMs",None); print(json.dumps(d,sort_keys=True))' \
  reports/seven-tile-batch-JOB_ID.json > /tmp/seven-remote.json
diff /tmp/seven-local.json /tmp/seven-remote.json
```

並列動作は`gs://BUCKET/jobs/JOB_ID/logs/time-v.txt`の`Percent of CPU this job got`で判定する。
100%を大きく超えていれば、分類フェーズが並列実行されている。

Mathlib cacheとLake build cacheをコンテナイメージへ含めるかは、イメージサイズと再ビルド時間を
初回試行で測って決める。

## 資源設定

既存のdevcontainer最低要件を初期値にする。

| ジョブ | 初期CPU | 初期メモリ | 初期永続データ容量 |
| --- | ---: | ---: | ---: |
| 4枚形 | 2 vCPU | 8 GB | 40 GB |
| 7枚形 | 8 vCPU | 32 GB | 40 GB |
| 10枚形 | 4 vCPU | 16 GB | 40 GB |
| 13枚形 | 32 vCPU | 128 GB | 100 GB |

13枚形は`CPUS_ALL_REGIONS`のクォータ上限32 vCPUに合わせて`n2-standard-32`を使う。
`/usr/bin/time -v`、生成物サイズ、worker別のメモリ使用量を記録し、実測後に構成を見直す。

Batchが投入する13枚形のパラメーターは次である。

```bash
lake exe thirteen-tile-report-gen \
  --generation-workers=32 \
  --classification-workers=16 \
  --buckets=256 \
  --work-dir=/tmp/mahjong-work-thirteen-tile/thirteen-tile-buckets
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

### 4枚形と7枚形

数分で終わるため、中断時はジョブ全体を再実行する。checkpointは持たない。

### 10枚形と13枚形

どちらも`MahjongComputations.BucketClassification`を通じて、bucketごとの分類結果を
`bucket-N.bin.result`としてbucketファイルの隣へ書き出す。生成フェーズは完了時に
`generation.done`を書き、再実行時に生成済みbucketを再利用する。workerはこのディレクトリを
`gs://BUCKET/checkpoints/JOB_TYPE/GIT_COMMIT/`へ定期的に同期し、起動時に復元する。

- 生成中断: 生成を最初からやり直す。生成途中のbucketは保存しない。
- 生成完了後の分類中断: 保存済みbucketを復元し、未完了bucketだけを分類し直す。

同期は生成が終わるまで何も送らない。生成中のbucketは`generation.done`が無ければ再利用できず、
かつ全bucketが伸び続けるため、送っても無駄になるからである。`generation.done`は、ほかの
全メンバーがアップロード済みかつアップロード後に変化していないと確認できたときだけ公開する。
これにより、途中まで書かれたbucketに完了印が付くことを防ぐ。

checkpointはジョブIDでなくGit commitで区切るため、同じcommitの再投入は前回の続きから始まる。
最初から計算し直すには`--fresh`を付ける。ジョブが成功すると、そのcommitのcheckpointは削除される。

再開した実行の`waitCoreCacheHits`、`waitCoreCacheMisses`、`waitCoreCacheEntries`は、
通しで実行した場合と必ず異なる。wait-coreキャッシュはプロセス内にしか存在せず、
再開したプロセスは復元済みbucketの分を計算しないためである。レポートのそれ以外の行は、
bucket単位の集計をbucket順にmergeするため、通し実行と同一になる。

## Cloud Storage上の配置

ジョブごとに独立したprefixを使う。

```text
gs://BUCKET/jobs/JOB_ID/
  request.json
  metadata.json
  logs/
    time-v.txt
  results/
    thirteen-tile-report.json
```

checkpointはジョブ間で共有するため、ジョブprefixの外に置く。

```text
gs://BUCKET/checkpoints/JOB_TYPE/GIT_COMMIT/
  generation.done
  bucket-0.bin
  bucket-0.bin.result
  ...
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

### Phase 0: 4枚形で環境疎通

- commit SHAで識別できる計算イメージをCloud Buildで作り、Artifact Registryへpushする。
- Spot VMで4枚形レポートを完走し、Cloud Storageへreport、metadata、`time -v`を保存する。
- checksum検証後にローカルへdownloadできることを確認する。
- dirty worktree、未検証・失敗report、既存ファイルへのdownloadが拒否されることを確認する。

### Phase 0.5: 7枚形で並列動作確認

- 8 vCPUのSpot VMで7枚形レポートを完走する。
- `time -v`の`Percent of CPU this job got`が100%を大きく超えることを確認する。
- `calculationElapsedMs`行を除いた内容がローカル結果と一致することを確認する。
- ジョブ種別ごとにmachine type、worker数、成果物名が切り替わることを確認する。

### Phase 1: 10枚形で疎通確認

- Phase 0で用意したGCPリソースとパッケージングを再利用する。
- Spot VMで10枚形レポートを完走する。
- VMが自動削除されることを確認する。
- ローカル結果と主要件数、checksumを比較する。
- 意図的な中断または失敗で再試行と上限到達を確認する。

実測結果（2026-10-09）:

- `e2-standard-4`、Spot、4 workers、再試行0回で成功した。
- 計算時間は297秒、wall timeは4分56秒、最大RSSは約0.75 GiBだった。
- CPU使用率は367%で、4 workerの並列実行を確認した。
- `calculationElapsedMs`行を除いたレポート本文がローカル結果と一致した。
- 初回は作業ディレクトリの書込権限問題で失敗したため、workerは一時ディレクトリから
  生成器を起動する構成へ修正した。

checkpoint機構を追加した後の再実行（2026-10-09、`8b1db16`）:

- 計算時間は285秒で、レポート本文はローカル結果と一致したままだった。
- `checkpoint_uploaded_files`は121で、生成済みbucketと分類済みbucketがCloud Storageへ
  同期されることを確認した。
- 成功時に`gs://BUCKET/checkpoints/ten-tile/COMMIT/`が削除されることを確認した。

### Phase 2: 13枚形の資源測定

- `n2-standard-32`、生成32 worker、分類16 worker、256 bucketから開始する。
- bucket生成時間、分類時間、最大RSS、bucketディレクトリのサイズを測る。
- 生成済みbucketと分類結果をCloud Storageから復元して再開できることを確認する。
- 実測に基づきmachine type、worker数、bucket数を更新する。

実測結果（2026-10-09、`8b1db16`）:

- `n2-standard-32`、Spot、生成32 worker、分類16 worker、256 bucket、再試行0回で成功した。
- wall timeは7時間10分22秒、`calculationElapsedMs`は25821955 ms（約7時間10分）だった。
  ローカル実行（生成16 worker、分類8 worker）の33144433 ms から約22%短縮した。
- 最大RSSは約13.6 GiBで、128 GiBのうち1割程度しか使わなかった。
  次回は`n2-highmem`系ではなく、より安価な構成やvCPU増強を検討できる。
- CPU使用率は656%で、32 vCPUに対して並列度が足りていない。
  bucket分布の偏りが律速とみられるため、bucket数の増加や分割方法の見直しが次の改善点になる。
- `generationWorkers`、`classificationWorkers`、`calculationElapsedMs`を除いたレポート本文が
  ローカル結果と完全に一致した。wait-coreキャッシュ統計も一致した（中断がなかったため）。
- `checkpoint_uploaded_files`は480、`checkpoint_restored_files`は0で、
  成功時に`gs://BUCKET/checkpoints/thirteen-tile/COMMIT/`が削除されることを確認した。
- Spot中断は発生しなかったため、実環境での再開動作はまだ未検証である。

### Phase 3: 必要な場合だけ細粒度化

- bucket別結果の永続化は実装済みなので、単一ジョブの再開で足りるかを実測で判断する。
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
