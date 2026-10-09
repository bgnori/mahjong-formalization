# リモート計算基盤の選定理由 2026-10-09

状態: GCP Batch + Spot VMの試行を決定

この文書は、重いレポート生成の外部計算基盤としてGCP Batch + Spot VMを試すと決定した時点の
Rationaleを記録する。現在の運用方針は
[remote-compute-gcp-batch.md](remote-compute-gcp-batch.md)を参照する。

## 背景

これまで重い計算は、ローカルマシンまたはGitHub Codespacesで実行していた。

- ローカルマシンはCPUとメモリが不足する。
- Codespacesにはidle timeoutがあり、接続状態を意識した長時間運用が必要になる。
- 13枚形は最低16 CPU、64 GB RAM、64 GB storageを想定する。
- 13枚形の分類はworkerごとにbucket内HashMapを持つため、CPU数だけでなくメモリ量が重要である。
- 13枚形は生成完了後のbucketを再利用できるが、生成途中と分類bucketごとのcheckpointはない。
- 13枚形規模では基盤にかかわらず、中断と再開を明示的に設計する必要がある。

当初はDevPodを使い、外部の常設VMや専用サーバーを開発環境として扱う案を検討した。しかし、
必要なのは常設の対話環境ではなく、短期間だけ大きな資源を借りるバッチ計算だった。希望する操作は
「ローカルでコマンドを実行するとリモートVMが起動し、計算と成果物保存を終えた後にVMが削除される」
というものである。

## 判断基準

優先順位を次のように定めた。

1. ローカルから簡単にジョブを投入できる。
2. ジョブ完了後に計算資源が自動削除される。
3. Spot中断後に自動再試行できる。
4. ローカル端末やIDEの継続接続を必要としない。
5. CPUと64 GB以上のメモリを、GPUを必須とせず選択できる。
6. アカウント、権限、常設control planeの管理を少なくする。
7. 中間生成物と最終結果をVM外へ永続化できる。
8. 実行commit、設定、資源、成果物を追跡できる。
9. 初期実装を小さく始め、必要な場合だけ細粒度checkpointへ進める。

価格の最小化だけを第一基準にはしなかった。安価でも、孤児VMの削除、Spot再投入、credential管理、
成果物回収を自作する必要がある構成は、利用頻度に対して運用コストが大きいと判断した。

## 決定

最初に試す基盤として、**Google Cloud Batch上のSpot VM**を採用する。

- ローカルのラッパーCLIからBatch jobを投入する。
- BatchがSpot VMを作成し、コンテナ化した計算を実行する。
- Spot中断時はBatchのtask retryで新しいVMへ再投入する。
- 中間生成物、レポート、メタデータはCloud Storageへ保存する。
- 計算イメージはArtifact Registryへ保存する。
- ジョブ終了後のVM削除はBatchへ任せ、ローカル終了処理に依存させない。
- 初期段階では単一ジョブの粗い再試行を使う。
- 実測で必要性を確認した後にだけ、bucket単位checkpointやBatch Array Jobを追加する。

この決定はGCP Batchを恒久採用すると確定するものではない。10枚形でライフサイクルと再現性を検証し、
13枚形の小規模または初回実行で資源、Spot在庫、再試行損失、費用を評価する。

## 比較した案

### ローカル実行

不採用理由:

- 現在のマシンパワーが不足する。
- 13枚形に必要なCPU・メモリを確保できない。

引き続き適する用途:

- 通常の開発、証明、テスト。
- 4枚形・7枚形レポート。
- リモート投入前の小規模確認。

### GitHub Codespaces

不採用理由:

- idle timeoutがあり、長い無人計算で接続維持を意識する必要がある。
- 大容量machineの利用可否が組織ポリシーに依存する。
- バッチ完了後の自動的な成果物回収と環境削除を中心にしたサービスではない。

引き続き適する用途:

- 一時的な開発環境。
- リポジトリのdevcontainer動作確認。

### DevPod + 常設VMまたは専用サーバー

不採用理由:

- DevPodは対話的なworkspace管理には適するが、今回の主目的はephemeral batch jobである。
- 短期間だけ計算する前提では、常設VMの停止、削除、disk、バックアップ管理が余分になる。
- DevPod workspaceの停止はコンテナ内プロセスも停止させるため、別途ジョブ管理が必要になる。

再検討条件:

- 対話的なリモートLean開発を日常的に行う。
- 同じ大容量ホストを高い稼働率で使うようになる。

### Hetzner Cloudまたは専用サーバー

不採用理由:

- 常設または明示的に作成・削除するサーバーとしては費用対性能がよいが、Spotの自動再投入を提供する
  バッチ基盤ではない。
- VMライフサイクル、再試行、成果物回収を自作する必要がある。
- 短期・低頻度利用では、安価な月額料金より運用作業の方が相対的に大きい。

再検討条件:

- 計算時間が増え、専用サーバーの月額利用がSpotより予測可能または安価になる。

### AWS Batch + EC2 Spot

要件は満たすが、最初の候補から外した。

- IAM role、Job Definition、Job Queue、Compute Environmentなど、今回の単一利用者・少数ジョブには
  管理対象が多い。
- AWSアカウントと権限管理の作業を増やしたくないという条件に合わない。
- 将来大規模化した場合の機能は豊富だが、現時点ではその利点を使わない。

再検討条件:

- 既存のAWSアカウント、IAM、監視、請求管理を流用できるようになる。
- AWS固有のinstanceやサービスが計算上必要になる。

### RunpodまたはVast.aiをAPI/CLIから直接操作

不採用理由:

- API key一つで開始しやすい点は魅力がある。
- 一方で、主市場はGPU計算であり、CPUと64 GB以上のRAMだけを効率よく借りられるとは限らない。
- CPU性能、ホスト品質、在庫のばらつきが大きい。
- Spot中断後の再投入、確実な成果物保存、ローカル端末停止後の監視、孤児instance削除を
  ラッパー側で実装する必要がある。
- 不要なGPU料金を含む可能性がある。

再検討条件:

- 実測可能なCPU/RAM構成がGCP Spotより十分安価で安定している。
- GCP BatchのSpot在庫またはアカウント管理が許容できない。

### SkyPilotまたはdstack

保留理由:

- SkyPilot Managed JobsはSpot中断からの復旧、自動削除、複数region/cloud探索を提供し、
  希望する操作に近い。
- dstackもYAMLで資源とタスクを定義し、RunpodやVast.aiのprovisioningを自動化できる。
- ただし、クラウド固有のBatchの上に追加のorchestration層、controller、設定、バージョン依存を
  導入することになる。
- 最初はGCP Batchだけで要件を満たせるため、抽象化層を先に追加しない。

再検討条件:

- GCP内でSpot在庫を確保できず、複数cloudへの自動failoverが必要になる。
- 同じジョブ定義を複数providerで継続的に実行する。
- GCP Batch固有コードの保守がSkyPilot/dstackの導入コストを上回る。

### Kubernetes

不採用理由:

- cluster、node pool、autoscaler、persistent volume、権限の管理が必要になる。
- 単一利用者の断続的なバッチ計算には過剰である。

再検討条件:

- 多数の独立ジョブを常時投入する。
- 複数利用者で計算資源を共有する。

## GCP Batchを選んだ理由

### バッチのライフサイクルがサービスの責務である

VMを直接作るスクリプトと異なり、ジョブ状態、task retry、VM作成と削除をBatchが管理する。
ローカル端末の終了やネットワーク断でcleanup処理が失われにくい。

### CPU・メモリ中心のmachine typeを選べる

GPUマーケットと異なり、GPU料金を支払わずに16 vCPU、64 GB以上のRAMを持つ構成を選べる。
初回は余裕のあるメモリ構成で最大RSSを測り、その後縮小できる。

### AWS Batchより初期管理対象を抑えられる

GCPでもproject、billing、service account、API、bucket、registryの初期設定は必要である。ただし、
単一利用者の初期試行では、常設のCompute EnvironmentやJob Queueを個別に管理せずに開始できる。

### 粗い再試行から段階的に始められる

現行の13枚形実装は生成完了を境界として再開できる。最初から分散schedulerを実装せず、
生成済みbucketをCloud Storageへ退避するだけで、分類中断時の生成やり直しを避けられる。

### 将来の細粒度化に移行できる

分類結果をbucket単位で独立させた場合、Batch Array Jobへ自然に移行できる。現時点では、
実測で必要性が確認されていない複雑性を導入しない。

## 受け入れた不利益

- Google Cloudのproject、billing、API、service account、Artifact Registry、Cloud Storageを
  一度は設定する必要がある。
- Spot VMは在庫不足で開始できない、または実行中に中断される。
- 再試行はプロセスをメモリ状態から再開するものではなく、永続化したcheckpointからの再実行になる。
- 初期実装では生成途中や分類bucketごとのcheckpointがないため、再計算が発生する。
- コンテナイメージのビルドと保存に時間と少額の費用がかかる。
- Cloud Storage、Artifact Registry、LoggingにはVM削除後も料金が残る。
- GCP固有のjob specとbootstrap手順を保守する必要がある。

これらは、常設サーバー管理、独自scheduler、複数cloud controllerを最初から導入するより小さいと
判断した。

## 検証で確認する仮説

次が成立しなければ、この決定を見直す。

1. 10枚形をSpot VMで完走し、ローカル実行と同じ結果を得られる。
2. 成功時と失敗時の両方で、Batchが計算VMを削除する。
3. Spot中断後に、人手を介さず再試行できる。
4. 13枚形に必要な16 vCPU、64 GB以上のSpot在庫を現実的な待ち時間で確保できる。
5. 生成済みbucketをCloud Storageへ保存・復元する時間と費用が許容できる。
6. GCPの初期設定と日常操作が、直接VMやAWS Batchより十分簡単である。
7. 実行時間と再試行回数を含む費用が、低頻度利用として許容できる。

## 見直し条件

次のいずれかが起きた場合は、プラットフォームまたはジョブ分割を再評価する。

- Spot中断が多く、最大再試行回数へ頻繁に到達する。
- 必要なmachine typeのSpot在庫が継続的に不足する。
- bucket archiveの転送が計算時間または費用を支配する。
- 13枚形分類の再実行損失が大きく、bucket単位checkpointが必要になる。
- 計算頻度が上がり、専用サーバーの方が安価になる。
- 複数cloudへの自動failoverが必要になる。
- GCPのアカウントまたは権限管理が期待より複雑になる。

## 参考資料

- [Google Cloud Batch documentation](https://cloud.google.com/batch/docs)
- [Create and run a basic job](https://cloud.google.com/batch/docs/create-run-basic-job)
- [Automate task retries](https://cloud.google.com/batch/docs/automate-task-retries)
- [Compute Engine Spot VMs](https://cloud.google.com/compute/docs/instances/spot)
- [SkyPilot Managed Jobs](https://docs.skypilot.ai/en/docs-examples/examples/managed-jobs.html)
- [Runpod CLI overview](https://docs.runpod.io/runpodctl/overview)
- [Vast.ai CLI](https://vast.ai/developers/cli)
