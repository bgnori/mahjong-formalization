# ドキュメント後に検討する項目

この文書は、ドキュメント整備の途中で見つかった設計・命名・概念整理の課題を管理する。
読解中に気づいた違和感をすぐにソース改変へつなげず、一通り説明を書いたあとで影響範囲を見て対応する。

## 扱い方

- ドキュメント作業中に見つけた課題を、ここへ短く記録する。
- すぐ直さない理由と、後で見るべき影響範囲を書く。
- ソース変更が必要な場合は、読解ドキュメントが一巡してからまとめて検討する。
- 単なる表記ゆれではなく、読者の誤解や設計変更につながるものを優先する。

## 課題一覧

### 通常形聴牌の手牌枚数規則を一元化する

状態: 対応済み

通常形聴牌の手牌枚数は `standardTenpaiHandSize mentsuCount` が表す `3n + 1` で決まるが、
`IsTenpaiHandSize` は有効な5個の値を選言で再列挙し、`Hand.lean` の名前付き定数の一部は
大きい手牌サイズから3を引く別の計算経路を持っていた。

`IsTenpaiHandSize` は、面子数が `0` 以上 `standardHandMentsuCount` 以下であり、手牌枚数が
`standardTenpaiHandSize` から得られるという有限存在条件へ変更した。`Hand.lean` の各サイズ定数も、
対応する面子数を同じ関数へ渡して定義する。これにより、対象範囲と枚数計算をそれぞれ
`standardHandMentsuCount` と `standardTenpaiHandSize` だけが決める。

また、`DirectWaitGeneration.lean` に局所定義されていた面子列の牌数補題は、
`Pattern.lean` の `MentsuCandidate.flatMap_tiles_length` と同じ内容だったため削除し、既存補題を直接使う。

`Hand` も、1枚、4枚、7枚、10枚、13枚ごとに同じ物理牌埋め込みを持つ5コンストラクタから、
`mentsuCount : Fin (standardHandMentsuCount + 1)` と
`Fin (standardTenpaiHandSize mentsuCount)` の牌を持つ1つの構造体へ変更した。これにより、合法な5サイズを
型で制限する性質を保ったまま、サイズ名、コンストラクタ、`toFinset` の分岐による同じ規則の再列挙を除いた。

### 分解の操作履歴と外延的な正しさを分離する

状態: 対応済み

`MentsuPartition` は、実行器の再帰構造に近い帰納的な証拠として、各段階の完成面子、
`removeTiles` の戻り値、残りの分解証拠を保存していた。

ドキュメント整備で、次の小定理と証明パターンが連続して現れた。

- `MentsuPartition.of_perm`: 除去履歴を別の入力順へ移す。
- `MentsuPartition.tiles_perm`: 各除去履歴から牌全体の保存則を復元する。
- `MentsuPartition.components_length`: 帰納段階と `fuel` の対応を列長として取り出す。
- 変更前の `WinningPartition.of_perm`: 雀頭除去後の残り長を揃えて、面子分解証拠を移す。
- `WinningPartition.tiles_perm`: 面子側の保存則へ雀頭除去の保存則を再び連結する。

証明の粒度が細かく見える主因は、必要な数学的性質が細かいというより、順序依存の操作履歴と
順序非依存の仕様が同じ証拠表現に重なっていることかもしれない。

面子分解の意味は次の外延的な条件だけで表せる。

```lean
components.length = fuel ∧
	(components.flatMap MentsuCandidate.tiles).Perm tiles
```

外延仕様は `MentsuPartitionSpec` と `WinningPartitionSpec` に名前を与えた。前者は部品数と
牌の順列が証明フィールドなので、各条件を射影できる `Prop` 構造体とした。後者は雀頭と面子列という
データの witness を含む。Leanでは `Prop` 構造体からデータ射影を生成できず、`Type` にすると仕様証明が
計算データを不必要に保持するため、名前付きの存在命題とした。

`MentsuPartition` と `WinningPartition` は、それぞれ同じ引数の外延仕様と概念的に重複していたため削除した。
再帰的な `decomposeMentsu` の健全性・完全性は、`fuel` に対する帰納法で `MentsuPartitionSpec` へ直接示す。

`mem_decomposeMentsu_iff_spec` と `mem_winningPartitions_iff_spec` により、どちらの列挙結果も
操作履歴を介さず外延仕様として読める。

公開側の `CompletionFor` は `WinningPartitionSpec` を保持するよう変更した。`DirectWaitGeneration` も
外延仕様を使い、完成形から分割を示す証明から `fuel` の算術、`removeTiles` の具体的結果、帰納的証拠の構築を
除いた。`WinningPartitionSpec.of_perm` は、全和了構成部品から入力牌列への順列と入力間の順列を
`List.Perm.trans` でつなぎ、雀頭と面子列を変えずに新しい入力の仕様を作る。

### `List` による有限探索として候補生成と成功条件を表す

状態: 一部対応

可約性判定は、完成面子を試しに1つ取り除き、残った牌列が聴牌であり、かつ待ち核集合を保つ枝が
存在するかを調べている。Leanでは、この種の有限探索を `List`、`Option`、`filterMap`、`do`記法、
必要に応じて `guard` で表せる。ほかの言語由来の探索語彙や記法を持ち込むより、Lean標準のリスト計算として
候補生成、失敗枝の破棄、成功条件を説明するほうが読みやすい。

現行コードでも、この有限探索はすでに `List` で表現されている。

- `MentsuCandidate.candidates`: 取り除く完成面子を選ぶ。
- `filterMap (removeTiles tiles)`: 実際に取り除けない候補を失敗枝として捨てる。
- `mentsuReductions`: 成功した残り牌列をすべて列挙する。
- `waitCorePreservingMentsuReductions`: 聴牌であり、待ち核集合を保つ成功枝だけを列挙する。
- `canReduceMentsuPreservingWaitCores`: 成功枝が存在するかをBoolで判定する。

`waitCorePreservingMentsuReductions` を先に置き、Bool判定をその結果の空でなさから導出することで、
「成功した探索枝そのもの」と「存在判定」を分離した。ここで新しい共通探索APIを作る必要は薄い。
`List` ベースの列挙関数を基礎にし、Lean 4 の標準的な `do`記法、`guard`、`filterMap` に寄せて書く。

今後の論点は、現在の `List (List Tile)` より多くの情報を返す必要があるか、実行用の列挙と命題側の仕様を
どう対応させるか、この書き方を他の探索へ広げる価値があるか、の3つに分けて扱う。

1つ目は、成功した枝の情報量である。現在の `waitCorePreservingMentsuReductions` は残り牌列だけを返すため、
可約性のBool判定には十分である。一方、レポートやデバッグで「どの完成面子を除いたのか」を示したい場合は、
除去した `WinningComponent` または `MentsuCandidate` と `remaining` をまとめた構造体を返すほうがよい。
さらに定理で使うなら、候補所属、`removeTiles tiles removed.tiles = some remaining`、待ち牌が残ること、
待ち核集合が一致することを証拠フィールドとして持つ証拠付き構造体にする選択肢もある。ただし、実行結果として
扱いたいデータと、証明だけに必要な証拠を同じ構造体へ入れると、計算や表示が読みにくくなる可能性がある。

2つ目は、Bool判定とProp仕様の対応である。実行用の `canReduceMentsuPreservingWaitCores` に対して、以前は
`canReduceMentsuPreservingWaitCores tiles = true` をそのまま包む
`CanReduceMentsuPreservingWaitCores` も公開していた。この別名は独立した外延仕様を与えず、利用箇所も実行判定の
言い換えに限られていたため削除した。可約性の分岐はBoolを直接使い、特徴付け定理は `= true` / `= false` を結論にする。

今後、証明向けの主仕様が必要になった場合は、単なるBool等式の別名ではなく、
「ある完成面子と残り牌列が存在し、除去に成功し、待ち核集合を保つ」という外延的な存在命題を定義する。
その前段として、`remaining ∈ waitCorePreservingMentsuReductions tiles` と外延条件の対応補題を検討する。

3つ目は、他の探索への展開である。`WaitCompletionFinder`、`Hand`、`DirectWaitGeneration` には、候補列挙、
失敗枝の破棄、成功結果の列挙を `flatMap` / `filterMap` で書いている箇所がある。共通APIへ抽象化するのではなく、
各箇所でLean 4の習慣に沿って `List` の `do`記法、`guard`、`filterMap` を使い分け、必要な場合だけ
「成功枝を返す関数」と「存在・個数・分類などの派生判定」を分ける。共通化より、局所的な読みやすさを優先する。

試行として、`findWaitCompletions` の待ち牌と和了分割の選択、および `seedCandidates` の完成形、選択部品、
待ち牌の選択を `List` の `do`記法へ変更した。複数段の候補選択が同じ字下げで並び、最後に結果を返す形になり、
この2箇所は入れ子の `flatMap` / `map` より探索手順を追いやすい。一方、単一の `Option` を捨てる
`mentsuReductions` の `filterMap`、再帰成功時と失敗時を明示する `Hand.fromTiles` の `flatMap` と `match`、
牌列そのものを連結する `flatMap` は、元の演算を明示する現在の形が読みやすい。表記は一律に置換せず、
連続する候補選択を平坦に読める場合に `do`記法を使う。

`findWaitCompletions` の `dedup` は、同じ待ち牌と同じ正規化済み和了分割へ至る探索経路の重複を除く。
たとえば `2345678m` では `dedup` 前に6件、後に3件となり、異なる3待ちを残しながら各分割の二重生成だけを除く。
これは、異なる待ち牌が同じコードを持つときにコードの重複を残す課題とは別である。コード多重集合を
`[338, 338, 338]` とする場合もFinder側の `dedup` は維持し、待ち牌を保持した3件をコードへ写した後で
コードだけの重複除去を行わない。候補列挙と重複除去の役割が見えるよう、Finderでは `do` ブロックを
局所変数 `candidates` に置き、その後で `candidates.dedup` とした。

面子候補を標準順にだけ選んで重複経路そのものを生成しない方法も考えられるが、探索器と
`MentsuPartitionSpec` の対応定理へ順序制約を追加し、完全性を改めて証明する必要がある。現在扱う面子数では
後段の `dedup` で十分であり、複雑化に見合う性能上の必要も確認されていない。この最適化案は現時点では
対応しないものとして検討を閉じる。`dedup` が除く対象は `findWaitCompletions` のコメントに記録した。

後で確認すること:

- 成功した除去面子と残り牌列を返す実行用構造体を追加すると、レポートやデバッグで有用か。
- 候補所属、除去成功、待ち牌の存在、待ち核一致を証拠として持つ構造体を、実行用データと分けて用意すべきか。
- `remaining ∈ waitCorePreservingMentsuReductions tiles` と、完成面子除去に関する存在命題の対応補題を短く証明できるか。
- 可約性の命題仕様が必要になったとき、Bool等式の別名ではなく存在命題として導入できるか。
- 探索順、重複候補、全解列挙、最初の解、解の存在判定を、同じ基礎表現から必要に応じて導出できるか。
- 新しい探索を追加するときも、連続する候補選択には `do`記法、単純な失敗枝の破棄には `filterMap`、
	データとしてのリスト連結には `flatMap` という局所的な使い分けが読みやすいか。
- 独自探索APIや探索エンジンを新たに作らず、現在のリスト実装と同等の計算可能性を保てるか。

### 待ち分解コード列の重複を保持する

状態: 対応済み（2026-10-28確認）

`waitDecompositionCodes` は、待ち牌付きentryをコードへ写した後も、異なる待ち牌に由来する同一コードの
出現回数を保持する。同じ待ち牌とコードの組に対する重複はentry生成時に除かれる。
実装は `WaitDecompositionCode.lean` の `waitDecompositionCodes` と `[26, 26]` の具体例で確認できる。
この仕様を [reading-order.md](reading-order.md) と [domain-vocabulary.md](domain-vocabulary.md) に反映した。

### Tanki実装変更後の可約・既約レポート差分を確認する

状態: 対応済み

Tanki関係の実装変更後に `fourTileReport` を再生成したところ、4枚形の集計で可約・既約の数が変わった。

- 旧: reducible 1674、irreducible 2082
- 新: reducible 1647、irreducible 2109

例として、`1223m` や `1233m` は旧レポートでは `reducible` だったが、新レポートでは `irreducible` になっている。
新しい実装では、単騎を完成面子付きの4枚終端としてではなく、完成面子を分離した後の核成分列として扱うため、
この差分は意図に沿っている可能性が高い。

旧実装の分類を維持せず、現行定義を仕様として採用する。完成面子を除去した後も
同じ待ち核集合を保つ場合だけを可約とし、`1223m` はコード `[21, 26]`、
`1233m` はコード `[26, 33]` を持つ既約例として回帰テストに固定した。
現行4枚形集計は reducible 1647、irreducible 2109 である。

### 待ち分解と待ち導出の語彙を分離する

状態: 対応済み

観測・コード化側を `WaitDecomposition`（待ち分解）、完成形からの直接生成側を
`WaitDerivation`（待ち導出）として分離した。

`WinningComponent` は待ち牌を除く前の和了構成部品、`WaitComponent` はそこから待ち牌を除いた結果、
または除去せず完成形のまま保持した部品である。具体牌を忘れた種別は `WaitComponentKind`、
種別だけの待ち分解は `WaitKindDecomposition` とした。

完成面子と核成分列を分離した結果は、牌姿全体の既約性を意味しないため `WaitCoreExtraction` とした。
直接生成モジュールは `DirectWaitGeneration`、待ち分解とコード化のモジュールは
`WaitDecompositionCode` とした。旧名の対応表は [obsolete-vocabulary.md](obsolete-vocabulary.md) に置く。

### `WellKnownWaitKind` が基本分類と通称・複合分類を同じ層に置いている

状態: 対応済み

人間向けの名前付き分類を機械的な待ち構造から分離するため、`WellKnownWaitKind`、
`WaitClassification`、`WaitProfile` と分類仕様・解析器を削除した。計算レポートは待ち牌、
待ち核を保つ可約性、待ち分解コードを直接扱う。

### 和了構成部品まわりの命名を整理する

状態: 対応済み

和了分割の部品は `WinningComponent` に統一した。通常の読者向け説明からは旧用語を外し、
移行用の対応表だけ [obsolete-vocabulary.md](obsolete-vocabulary.md) に分離した。

採用名の判断としては、`CompletedComponent` は待ち牌除去後の観測成分との「完成・不完全」の対比を強くしすぎ、
`StandardComponent` は標準形以外との比較を想定させ、`MeldOrPair` は実装表現を列挙するだけで
和了分割との関係を示さないため採用しなかった。

### 和了構成部品列の標準順が型で保証されていない

状態: 対応済み

`WinningComponent.canonicalize` は `List WinningComponent` を標準順へ並べるが、返り値自体は通常の
`List WinningComponent` である。そのまま `WaitCompletion.winningComponents` に保存すると、任意の順番の列と
標準順の列を型で区別できない問題があった。

対応として、標準順の和了構成部品列を表す `CanonicalWinningComponents` を導入した。
`WaitCompletion.winningComponents` はこの専用型を持つため、Finderが公開する結果は型の時点で
標準順であることを保持する。

現在の形:

```lean
structure CanonicalWinningComponents where
	components : List WinningComponent
	canonical : components = WinningComponent.canonicalize components
```

作成入口は次の関数に集約した。

```lean
namespace CanonicalWinningComponents

def ofList (components : List WinningComponent) : CanonicalWinningComponents :=
	-- `WinningComponent.canonicalize components` と、その標準順証拠を入れる

def toList (components : CanonicalWinningComponents) : List WinningComponent :=
	components.components

end CanonicalWinningComponents
```

`WaitCompletion` は次の形にした。

```lean
structure WaitCompletion where
	wait : Tile
	winningComponents : CanonicalWinningComponents
```

面子分解や通常和了分割の内部探索は、今までどおり `List WinningComponent` のままにした。
標準化が必要なのは、探索枝から公開結果 `WaitCompletion` を作る境界だけである。

代替案として、`SortedComponents` のような証拠付きsubtype
`{ components : List WinningComponent // components = WinningComponent.canonicalize components }` も考えられた。
ただし、フィールド名やAPIを読みやすく保つには、専用 `structure` のほうがよいと判断した。

単に `theorem WaitCompletion.winningComponents_canonical ...` を追加する案もあるが、任意の `WaitCompletion` を
直接構築できる限り、型上は不正な値を作れる。そのため、公開データの不変条件としては弱い。
今回の対応では採用しなかった。

`BEq` と `DecidableEq` は標準順リスト本体で比較する。
証拠フィールドの違いで値が別物に見えないよう、`CanonicalWinningComponents.ext` と比較用インスタンスを用意した。
`WaitCompletion` の外部手書き例は、リストを直接入れる形から `CanonicalWinningComponents.ofList [...]` へ変えた。

後で確認すること:

- 将来、`canonical` フィールドを `components = canonicalize components` ではなく、`Pairwise` などの
	順序述語に変える価値があるか。
- `CanonicalWinningComponents` のconstructorを隠し、`ofList` 経由の構築だけを公開する必要があるか。