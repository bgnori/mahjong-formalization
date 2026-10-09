# ドキュメント作成方針

この文書は、リポジトリ内のドキュメントを作るときの方針を定める。
読者向けの読書順そのものは [reading-order.md](reading-order.md) に置く。

## 役割分担

ソースコメントは局所説明、読者向けdocsは線形化された読書体験、語彙ページは重複回避の辞書として使う。

- ソースコメント: その定義や定理が麻雀待ち分類の中で何を意味するかを書く。
- [introduction.md](introduction.md): Lean4と証明付きプログラムが今回の用途で何を支えるかを説明する。
- [reading-order.md](reading-order.md): Lean未経験者が成果と正しさを追うための読む順番を示す。
- [lean-vocabulary.md](lean-vocabulary.md): Lean語彙の初出説明を集約する。
- [domain-vocabulary.md](domain-vocabulary.md): 麻雀待ち分類のプロジェクト語彙を集約する。
- [obsolete-vocabulary.md](obsolete-vocabulary.md): コードから削除した概念・用語・APIと、置き換え先または削除理由を記録する。
- [review-backlog.md](review-backlog.md): 説明中に見つかった設計・命名の検討事項を分離する。
- 運用方針文書: 現在採用している開発・計算環境の構成、手順、完了条件を記録する。
- 日付付きRationale文書: 基盤や設計を選んだ時点の背景、比較対象、判断理由、見直し条件を記録する。

運用方針は試行結果に応じて更新する。一方、日付付きRationaleは当時の判断を後から参照するための
記録なので、新しい判断で内容を上書きせず、後続のRationaleから参照する。

## 読者向け成果物の原則

読者向けの文書には、読者が今の成果を理解するために必要な情報だけを置く。
過去の名前、改名判断、ドキュメント作業上の都合、今後の整理方針は本文に混ぜない。

読者向け文書で優先するもの:

- 今読むべき順番。
- 現在のコード名と概念名の対応。
- その定義や定理が、成果と正しさのどこを支えるか。
- 先に知っておくと読める語彙。
- ソフトウェアと証明に関するイントロダクション（一般論）

読者向け文書から外すもの:

- obsoleteになった用語の説明。
- 改名候補や採用しなかった名前の比較。
- ドキュメントの作り方そのもの。
- 保留中の設計論点。

外した情報は、用途に応じて [obsolete-vocabulary.md](obsolete-vocabulary.md)、[review-backlog.md](review-backlog.md)、
[proof-comment-policy.md](proof-comment-policy.md) に置く。

## 説明上の依存関係

文章は1次元にしか読めないため、コード上の依存関係と説明上の依存関係を分けて扱う。

- コード上の依存関係: Leanファイルがどの定義や定理を使っているか。
- 説明上の依存関係: 読者がその説明を理解するために先に知るべき概念や語彙。

読書体験では、説明上の依存関係を優先する。同じLean語彙の説明を各定理で繰り返さず、初出時に
[lean-vocabulary.md](lean-vocabulary.md) へ集約する。麻雀待ち分類のプロジェクト語彙は
[domain-vocabulary.md](domain-vocabulary.md) に集約する。