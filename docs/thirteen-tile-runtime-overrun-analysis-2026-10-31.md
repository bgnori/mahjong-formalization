# 13枚形計算の14時間超過と再試行の分析

調査日: 2026-10-31。以下の進捗は同日10:42 JSTまでの観測であり、完了報告ではない。
実行中ジョブの停止、再投入、設定変更は行っていない。

## 要約

- 中断の直接原因は、Batch taskの`maxRunDuration=50400s`（14時間）への到達。
  Spot回収、VM再起動、OOMを示す終了理由ではない。
- 導出生成は約155秒で終了しており、時間超過は分類段階で発生した。
- 旧実行から全牌姿への病的構造判定が追加されている。処理内容が異なるため、
  旧実行の約6時間40分、または以前の約7時間10分を現在の所要時間とはみなせない。
  追加判定は増大要因の有力候補だが、寄与率は未計測。
- 分類は32 vCPU中16 workerで動作する。初回試行の分類中の長期平均CPU使用率は
  VM全体で約19.0%（約6.08 core相当）。開始直後の約35%は持続しなかった。
- 256 bucket中、実データを持つのは64個。非空bucketのファイルサイズ差は約0.032%しかなく、
  今回は「一部のbucketだけ入力件数が突出した」とは説明できない。
  一方、1 bucketに約5.6～6.4時間を要し、分割・途中保存の単位が粗い。
- 初回は非空bucketの32/64個まで完了して中断した。完了済み174 bucketは全件再利用したが、
  途中だった16 bucketの処理はやり直した。これは初回超過の原因ではなく、その後の総時間を増やす要因。

14時間は現在の設定上限であり、現在の分類内容の実測で裏付けられた完了予測ではない。
設定値を増やすだけでは、分類自体の計算量やCPU利用効率は改善しない。

## 対象と証拠

| 項目 | 値 |
| --- | --- |
| Job ID | `mahjong-thirteen-tile-6a2b4f7e-20261030-053317-846fba` |
| Job UID | `mahjong-thirteen-t-e01c3702-266a-4bed0` |
| 実行commit | `6a2b4f7ea4672ed1565cb203f63a77932f93998b` |
| VM | `n2-standard-32`、32 vCPU、128 GiB、Spot |
| 並列数 | 生成32、分類16 |
| bucket数 | 256 |
| 制限 | 1試行14時間、最大再試行3回 |

Batch taskの`statusEvents`、Cloud Loggingの`batch_task_logs`、
Compute EngineのCPU utilization、Cloud Storageのcheckpoint一覧を照合した。
時刻は以下すべてJST。CPUは5分平均値を使用した。

| 時刻 | 観測 |
| --- | --- |
| 10/30 14:44:30 | 初回task開始 |
| 14:44:50 | 生成開始。復元checkpointは0個 |
| 14:47:25 | 93,251,547件の導出生成完了、分類開始 |
| 20:23:59～20:26:52 | 最初の非空16 bucketが完了 |
| 10/31 02:32:30～02:48:12 | 次の非空16 bucketが完了 |
| 04:44:40 | 実行上限超過、終了コード`50005`。attempt 0失敗 |
| 04:45:10 | 同じVM上で再試行開始 |
| 04:46:01 | 431ファイル復元。導出93,251,547件と分類済み174 bucketを再利用 |
| 10:31:21まで | 再試行の完了ログは再利用分込み238 bucket |

画像の04:45ごろのCPU再上昇は、この自動再試行と一致する。
VM IDは`770973858454409424`で、初回と再試行で変わっていない。

## 1. 旧実績と現在は分類する内容が異なる

同じ生成32・分類16 workerの比較対象として、次の成功済み実行を確認した。

| 項目 | 2026-10-11の旧実行 |
| --- | --- |
| Job ID | `mahjong-thirteen-tile-a0b1df03-20261011-073255-26e8c8` |
| commit | `a0b1df0374bc564e63a0fbafbefb1b9e9e1a9458` |
| `time -v` wall time | 6:40:27 |
| レポートの`calculationElapsedMs` | 24,025,094 ms |
| CPU使用率 | 668%（約6.68 core） |
| 最大RSS | 14,306,852 KiB（約13.64 GiB） |
| 導出数 / tenpai牌姿数 | 93,251,547 / 54,747,045 |
| reducible / irreducible | 54,707,433 / 39,612 |

旧実行では、[addShapeReport](../MahjongComputations/BucketClassification.lean)の
reducibility判定後、reducibleなら件数加算で戻っていた。
現在はその分岐前に`waitPathologyWitnessesShared`と病的構造の集計を実行する。
旧実行で約99.93%を占めたreducibleな牌姿にも追加処理が入る。

さらに、[従来のreducibility判定](../MahjongComputations/Common.lean)は
同じwait coreを持つ面子除去を見つけると探索を打ち切るのに対し、
[waitPathologyWitnessesWith](../Mahjong/WaitDecompositionCode.lean)は
`mentsuReductions`を最後まで走査する。除去候補ごとに共有cacheを参照し、
待ち集合やcore集合の比較も行う。元のwait core、面子除去候補も両判定でそれぞれ計算する。
cache hitであっても、キー生成・同期・集合比較などが無料になるわけではない。

**確定しているのは処理量が増える経路が追加されたこと**であり、
「病的構造判定だけで何倍遅くなったか」は、同じ入力での区間計測またはA/B測定なしには確定できない。
動的割当への変更も同時に含まれるため、今回の総時間差だけでその効果や退行を判定できない。

## 2. 長期のCPU使用率は開始直後より低い

Compute Engineの`compute.googleapis.com/instance/cpu/utilization`について、
同じVMの5分平均値を期間内で平均した。GNU `time`のCPU使用率とは分母が異なる。

| 期間（JST、5分平均点の終端で選択） | 点数 | VM全体CPU | core換算 |
| --- | ---: | ---: | ---: |
| 初回 10/30 14:50～10/31 04:40 | 166 | 19.01% | 6.08 |
| 初回の開始付近 14:50～15:20 | 6 | 33.98% | 10.87 |
| 初回の末尾付近 10/31 02:40～04:40 | 24 | 16.94% | 5.42 |
| 再試行 10/31 08:40～10:40 | 24 | 18.12% | 5.80 |

分類16 workerなので、1 workerが1 coreを占有すると仮定した上限はVM全体の50%。
実測19.01%はその約38%に相当する。32 vCPUを割り当てても、32 coreを使った計算にはなっていない。
旧実行の668%と比べても、長期に並列利用が改善したとは言えない。
ただし、VM指標には他プロセスも含まれ、GNU `time`との厳密な直接比較ではない。

低CPUだけで原因をlock競合、I/O、GC、single-flight待ちのいずれかに特定することはできない。
[共有cache](../MahjongComputations/Parallel.lean)にはstripe mutexと、
同じキーの計算完了を待つpromiseがあるため、候補として区間計測が必要。
cacheのstripe選択もキーの`% 64`であり、10枚の除去後牌姿はキーが`2 mod 4`なので、
そのlookup先は64 stripe中16 stripeに限られる。ただし、これが支配的な待ち時間かは未検証。

## 3. 入力量の偏りよりも、分類単位の粗さが確認できる

[外部bucketの選択](../MahjongComputations/ExternalWaitCompletion.lean)は
`tileMultisetKey % bucketCount`。基数5のキーは牌数13の場合`1 mod 4`なので、
データが入るbucketは`1, 5, ..., 253`の64個に限定される。

Cloud Storage上の256個の生成済みファイルを確認すると、192個はheaderだけの8 bytes。
非空64個は最小27,680,025、最大27,688,974 bytesで、差は最小に対して約0.032%だった。
ファイルサイズはほぼ均等だが、牌姿数、除去候補数、cache miss数まで均等と保証するものではない。

初回試行の非空bucketの経過時間は次のとおり。
時間にはbucket読込・group化・分類・結果保存を含み、CPU timeではない。

| 非空bucket群 | 個数 | 最小 | 中央値 | 最大 |
| --- | ---: | ---: | ---: | ---: |
| 最初の16個（番号1～61） | 16 | 5.609 h | 5.633 h | 5.657 h |
| 次の16個（番号65～125） | 16 | 6.139 h | 6.165 h | 6.382 h |

最初の16個が終わるまで、動的キューでも次の非空bucketには進めない。
32個が完了した時点ですでに分類開始から約12時間経過しており、
14時間上限の中で残り半分を終える余裕はなかった。
仮に後続も同程度なら、64個を16 workerで処理する4波には約22～26時間を要する。
これは粒度の問題を示す概算であり、cacheの温まりや再試行を無視した完了時刻予測ではない。

単にbucket数を増やしても、生キーの剰余方式のままでは空bucketの問題は残る。
また、細分化は単一bucketの待ちや再計算損失を減らし得るが、総分類処理量自体は減らさない。

## 4. 再試行による追加損失

中断前の完了174個は「非空32個 + 空142個」。
復元431ファイルは「生成256個 + generation marker 1個 + 分類結果174個」と一致し、
再試行ログでも174個すべての分類結果の再利用を確認した。
checkpoint同期漏れで完了済みbucketを失った証拠はない。

一方、[classifyBucket](../MahjongComputations/BucketClassification.lean)は
bucket全体の処理後にだけ結果を保存する。queue順と完了時刻から、
中断時は次の16個（番号129～189）が処理中だったと推定できる。
それぞれ約1.94～2.20時間、合計約33.76 worker-hours分の途中処理を失った計算になる。
これは待ち時間を含むworker経過時間であり、CPU-hoursや課金時間の合計ではない。
さらに[再開時には共有cacheを新規作成](../MahjongComputations/ThirteenTile.lean)するため、
cache再構築の追加コストもあり得るが未計測。

10:42時点の完了238個は「非空48個 + 空190個」。
非空だけでは48/64個、75%であり、「238/256なので93%終了」と所要時間へ換算してはいけない。
残りは非空16個と空2個。再試行にも14時間上限があるため、
未完了なら同日18:45ごろに再び中断され得る。

## 完了後の検証と次回の改善順序

1. **今回の完了を待つ。** 最終レポート、`metadata.json`、`logs/time-v.txt`、
   `logs/classification-timings.tsv`を取得する。
   最終試行のtimingでは`reused=true`は読込時間であり、過去の分類時間ではない。
   初回ログと再試行ログも併せて保存し、ジョブ全体の経過時間と最終試行の時間を分ける。
   強制終了した初回の`time -v`やmetadataは保存されておらず、最終試行の値で代用しない。
2. **分類内訳を測る。** bucket読込・group化、reducibility、病的構造判定、集計の各時間と、
   cache lookupのhit/miss、promise待ち、mutex待ちを区別する。
   実行中ジョブには計測コードを差し込まない。
3. **追加判定の重複処理を検討する。** 同じ牌姿のcore計算・面子除去・cache lookupを
   共有できるか確認する。判定結果やwitnessの意味・順序を変えない回帰テストが前提。
4. **bucket分布と保存粒度を見直す。** 単純剰余の制約を除き、全bucketを使用する。
   形式を変える場合は旧checkpointと識別し、現在の結果を誤再利用しない。
   bucket内部のcheckpointは複雑さとの比較で判断する。
5. **その後にworker数と実行上限を再設定する。** 32 worker化だけで速くなるとは限らない。
   同じ内容でCPU、RSS、wall timeを比較してから、現行の処理量に合う試行上限を設定する。
   旧実行の約13.6 GiBを、追加判定後のメモリ使用量の保証として使わない。

調査時点では分類処理内訳、現在の最大RSS、待ち時間、最終cache統計がない。
したがって、病的構造判定・cache競合・GC・I/Oの寄与率や最終完了時刻は確定していない。

## 再確認用の読み取りコマンド

```bash
PROJECT=mahjong-formalization
JOB=mahjong-thirteen-tile-6a2b4f7e-20261030-053317-846fba
COMMIT=6a2b4f7ea4672ed1565cb203f63a77932f93998b

gcloud batch tasks describe 0 --job="$JOB" --task_group=group0 \
  --location=us-central1 --project="$PROJECT" --format=json

gcloud logging read \
  'labels.job_uid="mahjong-thirteen-t-e01c3702-266a-4bed0" AND logName="projects/mahjong-formalization/logs/batch_task_logs" AND timestamp>="2026-10-30T05:30:00Z" AND timestamp<="2026-10-31T01:42:00Z"' \
  --project="$PROJECT" --limit=1200 --order=asc --format=json

gcloud storage ls -l \
  "gs://mahjong-formalization-compute/checkpoints/thirteen-tile/$COMMIT/"
gcloud storage ls -l \
  "gs://mahjong-formalization-compute/jobs/$JOB/"
```

成功後はcheckpointが削除されるため、その時点の一覧から過去の状態は復元できない。
ログの取得上限に達した場合は時間範囲を分ける。上記範囲では594ログを確認した。
CPUの再確認はMonitoring APIの`projects/mahjong-formalization/timeSeries`で
`compute.googleapis.com/instance/cpu/utilization`、instance ID `770973858454409424`を指定し、
`ALIGN_MEAN`、`alignmentPeriod=300s`で取得する。
