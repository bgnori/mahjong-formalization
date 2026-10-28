# プロジェクトレビュー報告 2026-10-28

## 総評

主要なLeanライブラリ、計算レポート生成、外部bucketの分類・再開処理、GCP Batch用スクリプト、
レポートViewerと関連文書を確認した。Leanの主要ターゲットとPython回帰テストはすべて成功した。
今回確認した範囲で、再現可能な実装不具合や証明の未完成箇所（`sorry` / `admit` / `axiom`）は見つからなかった。

一方、`waitDecompositionCodes` の重複保持仕様をすでに実装しているにもかかわらず、読書ガイドと
レビュー・バックログに旧仕様が残っていた。現行ガイドとバックログはこのレビューで更新した。
2026-09-10付のレビュー報告は当時の記録として維持し、本報告でその後の仕様変更を補足する。

## 対象と確認方法

- `Mahjong/` の牌・待ち探索・直接生成・待ち分解と可約性の主要実装
- `MahjongComputations/` の外部record形式、bucket分類、レポートJSON
- `MahjongTests/`、`scripts/`、`examples/` の回帰テスト
- GCP Batch用 `scripts/remote_compute.py`、静的レポート生成とViewer
- README、語彙・読書順、レビュー・バックログ

実施した確認:

- `sorry`、`admit`、`axiom`、`unsafe` をプロジェクト実装で検索
- `waitDecompositionCodes` のAPI、例、レポート分類での利用を照合
- 外部bucketのrecord読み書き、分類結果の再開、checkpoint同期の実装と関連テストを確認
- ViewerがJSON／アップロードファイルをDOMへ表示する箇所を確認
- Lean buildおよびPython unittestを実行

## 所見

### 1. 待ち分解コードの仕様説明が実装に追随していない

**重要度:** 低  
**状態:** 対応済み

現行の `waitDecompositionCodes` は、待ち牌付きentryをコードへ写した後、昇順に整列し、
異なる待ち牌から同じコードが得られた場合もその出現回数を保持する。
たとえば実装中の例は、異なる2つの待ち牌に同じコード26が対応する場合に `[26, 26]` を返す。
一方、`docs/reading-order.md` と `docs/review-backlog.md` には、コード列の重複を除く旧仕様と、
重複保持が未決である旨が残っていた。誤った分類仕様の理解や、すでに完了した変更の再提案につながる文書ドリフトである。

本レビューで読書ガイドを現行仕様に修正し、バックログ項目を対応済みに更新した。
APIの重複保持は「異なる待ち牌付きentryごとのコード出現回数」を表すものであり、
コード列単体から対応する待ち牌までは復元できない点も記載した。

関連箇所:

- [WaitDecompositionCode.lean](../Mahjong/WaitDecompositionCode.lean) — `waitDecompositionCodes` と `[26, 26]` の例
- [reading-order.md](reading-order.md) — APIの情報量と重複の説明
- [review-backlog.md](review-backlog.md) — 対応状況
- [domain-vocabulary.md](domain-vocabulary.md) — 多重集合としての現行仕様

### 2. 外部record形式の単体テストを追加する余地

**重要度:** 低（改善提案、現時点で不具合は未確認）

10枚形・13枚形の計算は、固定幅recordへのencode/decodeと大容量bucketの読み書きに依存する。
codecはヘッダー、レコード長、index範囲を検査する実装だが、今回確認したテスト群には
正常系のround-trip、truncated record、範囲外index、ヘッダー不一致を直接検査する専用テストが見当たらなかった。
大規模計算の中で問題が表面化する前に、小さな単体テストで形式の互換性と破損入力時の失敗を固定することを推奨する。

この項目はテスト保護の改善提案であり、現行のcodecに誤動作があることを示すものではない。

## 検証結果

以下はすべて成功した。

- `lake build Mahjong MahjongTests MahjongComputations`
- `python3 -m unittest discover -s scripts -p 'test_*.py'` — 20 tests
- `python3 -m unittest discover -s examples -p 'test_*.py'` — 9 tests

GCP上の実ジョブ投入・Cloud Storage同期は実施していないため、クラウド実環境に依存する動作は
ローカルの回帰テストと実装確認の範囲に限る。

## 推奨事項

1. 外部record形式に、encode/decode round-tripと不正・切断入力の小規模テストを追加する。
2. 2026-09-10付の旧レビューを現行仕様と混同しないよう、本報告を最新のレビュー結果として参照する。
