# 13枚形のbucket分類を動的割当にする

13枚形の分類は、牌姿を256個の外部bucketへ分け、複数workerで分類する。従来はbucket一覧をworkerごとの固定チャンクに分けていたため、処理の重いbucketが一部のworkerに集中すると、他のworkerが先に終了しても全体は最後のworkerを待つ。

`BucketClassification.classifyBuckets`は、共有キューからworkerがbucketを1つずつ取得する方式を使う。bucket単位の処理とcheckpointは維持し、完了したbucketの結果は従来どおり保存する。集計には入力時のbucket順を使い、workerの完了順によってレポート中のグループ順が変わらないようにする。分類ログにはbucketごとの経過時間を出し、負荷の偏りを調べられるようにする。

## 短時間の回帰確認

通常の並列計算テストは、小さな人工タスクと1面子のbucket分類だけで動的割当を確認する。13枚形全件の導出・分類は行わない。

```bash
lake build parallel-computation-test
lake exe parallel-computation-test
```

テストは、処理中のworkerがいても別のworkerが次の項目を取得すること、結果が入力順で返ること、1 workerと複数workerのbucket分類結果が一致することを確認する。

## 実データで性能を比較する場合

### 当面の推奨方針

本番CLIにはbucket部分選択を追加しない。部分集計を正式な13枚形レポートと誤認する可能性があり、少数bucketでは共有cacheや負荷分布も全件実行を代表しないためである。次に必要となる13枚形の全件実行で、bucket別時間、CPU使用率、wall timeを採取して動的割当の効果を評価する。結果だけでは判断できない場合に限り、正式レポートを生成しない専用ベンチマーク入口を検討する。

現行の13枚形レポート実行器には、分類対象bucketの部分選択機能がない。`--work-dir`で作業場所を分けられるが、通常実行では全256 bucketを分類するため、これを短時間テストとして実行しない。短時間の分類回帰確認は上記の4 bucketを使うテストで行う。

13枚形の実データで部分比較を行う場合は、別途、小さなベンチマーク入口を用意してから実施する。入力には、完結した牌姿グループを含むbucketを選び、同じファイル群を静的方式・動的方式の両方に渡す。現行CLIだけではこのA/B比較を再現できないため、今回の変更の検証として全件計算を走らせる必要はない。

ベンチマーク入口を追加した後は、まず少数bucketで試し、必要な場合だけ全256 bucketへ拡大する。試行ごとに別の作業ディレクトリへbucketをコピーし、分類結果ファイル（`.result`および`.result.part`）を除く。結果ファイルが残っているとcheckpoint再利用で分類が省略され、計測にならない。

比較する値:

- 同一bucket集合に対するwall timeと`time -v`のCPU使用率。
- ログに出るbucketごとの経過時間。特に最大値と中央値、長いbucketの偏りを見る。
- 出力レポートの分類件数とグループ順を含む内容の一致。
- 最大RSS。共有cacheは全workerで共用されるため、worker数を増やした時のメモリも確認する。

worker数の比較例は1、4、8、16。時間は環境依存なのでCIの合否条件にはせず、回帰テストでは正しさ、専用ベンチマークでは性能を評価する。

## 全件実行で保存される計測値

分類完了時に、作業ディレクトリへ`classification-timings.tsv`を原子的に書き出す。各行にはbucket path、checkpointから再利用したか、今回のプロセスで要した時間（ms）を記録する。GCP Batch実行では次の成果物を保存する。

- `logs/classification-timings.tsv`: bucket別時間。
- `logs/time-v.txt`: GNU `time -v`の全出力。
- `metadata.json`の`performance`: CPU使用率、wall time、user/system CPU time、最大RSS。

再開実行では、再利用されたbucketの時間は分類時間ではなくcheckpoint読込時間になるため、`reused`列で区別する。動的割当そのものの評価には、中断なしの全件実行、または各試行で新規に分類されたbucketの行を使う。

## 結果の読み方と次の手

動的割当で長いbucketの後に短いbucketを他workerが処理できるようになり、CPU使用率とwall timeが改善するかを見る。改善しない場合は、生成時のbucketキー分布、bucket内の牌姿数、共有cacheの競合、I/O待ちを次に調べる。bucket数を変更する試行は生成checkpointのbucket数と一致しなくなるため、導出生成を再実行する必要がある。まずは既存bucket数のままworker割当だけを比較する。

## 2026-10-30実行中の効率観測

ジョブ`mahjong-thirteen-tile-6a2b4f7e-20261030-053317-846fba`を
`n2-standard-32`、生成32 worker、分類16 worker、256 bucketで実行した。
以下は分類開始約10分時点の暫定観測であり、最終結果ではない。

- 93,251,547件の導出生成は約2分35秒で完了した。
- 分類中のVM全体の平均CPU使用率は約35.33%だった。32 vCPUに対して約11.3 core相当、
  分類16 workerの理論上限である約50%に対して約71%の利用率に相当する。
- CPU使用率は分類開始直後に約50%まで上がった後、約35%へ低下した。
- 最初に46 bucketが0～1 msで完了し、その後は16個の重いbucketを処理し続けた。
  この時点では重いbucketはまだ完了していなかった。
- 動的キューが入力順と異なる順番でbucketを完了し、空いたworkerが次を取得することは確認できた。
  ただし、重いbucketの完了前なので、固定割当と比べたwall time改善はまだ判断できない。

13枚形では牌姿の総枚数が常に13であり、`tileMultisetKey`の基数5は4を法として1なので、
`tileMultisetKey % 4 = 1`となる。このため、bucket番号を単純に
`tileMultisetKey % 256`とすると、実データは主に`1, 5, 9, ...`の64 bucketへ入り、
残りの約192 bucketは空になる。256 bucketを用意しても、負荷分散粒度は実質64 bucketである。

次回の改善候補:

1. bucket indexを生のキーの剰余ではなく、固定剰余を除いた値または適切なhashから計算し、
   256 bucket全体へ分散する。
2. 旧実行の最大RSSは約13.6 GiBで128 GiBに余裕があったため、分類workerを16から32へ
   増やして比較する。
3. bucket内部の処理は直列なので、worker数を増やしてもCPU使用率が伸びない場合は、
   共有wait-core cacheの競合、GC、bucket読込・group化を個別に計測する。
4. 最終的な判断には、`classification-timings.tsv`の非再利用bucketだけを使い、
   wall time、CPU使用率、最大・中央値bucket時間、実効非空bucket数を比較する。

前回のCPU使用率656%（約6.56 core）に対して暫定値約11.3 coreは改善しているが、
32 vCPU全体は使い切れていない。病的構造判定の追加コストもあるため、実行中の情報だけでは
3時間完了を支持できず、最初の重いbucket群と最終計測値を待って評価する。
