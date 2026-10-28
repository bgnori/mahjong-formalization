# Lean未経験者向けの読む順番

この文書は、Leanを知らない読者が麻雀待ち分類の成果と正しさを追うための読み順を定める。
未知のLean語彙は [lean-vocabulary.md](lean-vocabulary.md)、麻雀待ち分類のプロジェクト語彙は
[domain-vocabulary.md](domain-vocabulary.md) を参照する。

## 最初の入口

1. [introduction.md](introduction.md) で、Lean4と証明付きプログラムが今回の用途で何を支えるかを読む。
2. [lean-vocabulary.md](lean-vocabulary.md) の「最小語彙」を読む。
3. `Mahjong/Basic.lean` の牌種定義を読む。
4. `Tile.all` が34種類の牌種一覧であることを読む。
5. `Tile.mem_all` が、その一覧に抜けがないことを保証していることを読む。

この段階では、証明の細部をすべて追う必要はない。まずは「どの一覧に対して、何を保証しているか」を
理解する。

## 全体の道筋

この文書は、次の順番で実装と正しさをたどる。

1. `Basic.lean`、`Pattern.lean`、`Hand.lean` で牌、和了構成部品、物理牌を表す。
2. `WaitCompletionFinder.lean` で牌の除去、面子分解、通常和了分割、待ち牌、Finderを結ぶ。
3. `WaitDecompositionCode.lean` でFinderが得た待ち分解から段階的に情報を忘れ、コード化する。
4. `DirectWaitGeneration.lean` で完成形から待ち導出を直接生成し、既存Finderとの完全対応と有限添字を示す。

各節の「読む前に知る語彙」に未知の項目があれば、先に [lean-vocabulary.md](lean-vocabulary.md) を参照する。
麻雀固有の「待ち核」「可約」「待ち分解」「待ち導出」などは [domain-vocabulary.md](domain-vocabulary.md) にまとめている。

## 物理牌の枚数を読む

次の実例は、麻雀牌の山の枚数を示す `deck_cardinality` である。

読む前に知る語彙:

- `abbrev`
- `Finset`
- `.card`
- `theorem`
- `simp`
- `rfl`

ここでは、牌種 `Tile` と「同じ牌種が4枚ある」ことを表す `PhysicalTile` を区別する。
`deck_cardinality` は、物理牌全体の有限集合 `deck` の枚数が `deckSize` と一致すること、つまり
通常の麻雀牌の総数と同じになることを確認する。

## 物理牌としての手牌を読む

次のまとまりは、`Hand.lean` の `Hand` と `Hand.tileTypes` である。

読む前に知る語彙:

- `structure`
- `Fin`
- `↪`
- `List.ofFn`

`Hand` は、通常形聴牌として扱う面子数 `mentsuCount` と、その面子数に対応する枚数の物理牌を持つ。
`mentsuCount` は `Fin (standardHandMentsuCount + 1)` なので、0面子から4面子までの範囲に型で制限される。
手牌枚数は `standardTenpaiHandSize mentsuCount`、つまり `3n + 1` で決まる。

`tiles` の型は `Fin (standardTenpaiHandSize mentsuCount) ↪ PhysicalTile` である。
左辺の `Fin` は手牌内の位置を表し、右辺の `PhysicalTile` は「牌種と4枚中の何枚目か」の組を表す。
`↪` は埋め込みなので、同じ物理牌が2回現れないこともこの型が担う。

一方、通常形の待ち判定は物理牌そのものではなく、牌種 `Tile` の列を扱う。
`Hand.tileTypes` は `List.ofFn` で各位置の物理牌を取り出し、その第1成分だけを並べて `List Tile` に変換する。
同じ牌種の別の物理牌は同じ `Tile` として現れるため、ここから先の探索では牌種ごとの枚数をリストの重複として読む。

## 牌の表示形式を読む

次のまとまりは、`Basic.lean` の `TileFormat` と `Tile.format` である。

読む前に知る語彙:

- `inductive`
- `def`
- `match`
- `example`
- `rfl`

`Tile.format` は、Lean上の牌種 `Tile` を読者が見慣れた文字列へ変換する。
`unicode` は麻雀牌のUnicode文字、`mpsz` は `1m`、`9p`、`5z` のような牌譜表記である。

この表示形式を先に読むと、次の対子や順子の例で、Lean上の牌種列が実際の牌姿としてどう見えるかを確認しやすくなる。

## 通常形のサイズと開始位置を読む

次のまとまりは、`Pattern.lean` 冒頭の手牌サイズと `ShuntsuStart` である。

読む前に知る語彙:

- `abbrev`
- `def`
- `Fin`
- `Bool`

ここでは、通常形の手牌枚数や、順子の開始位置を表す補助定義を読む。
開始位置を `Fin` で表すことで、存在しない開始位置を型で除外している。
`ShuntsuStart.firstRank`、`middleRank`、`lastRank` は順子の3枚を計算する。

## 麻雀の小部品とデータ構造を読む

次のまとまりは、`Pattern.lean` の `Toitsu`、`Shuntsu`、`MentsuCandidate` である。

読む前に知る語彙:

- `inductive`
- `namespace`
- `def`
- `List Tile`
- `example`
- `rfl`

ここでは、麻雀上の概念とLean上のデータ構造の対応を先に押さえる。

- `Toitsu`: 同じ牌種2枚からなる対子。
- `Shuntsu`: 同じスートで連続する3枚からなる順子。
- `MentsuCandidate`: 通常形で完成面子として扱う候補。順子または刻子。

それぞれの `tiles` は、その部品を構成する牌種列を返す。
`Tile.format .mpsz` を使った `example` により、対子、順子、刻子が実際の牌姿としてどう見えるかを確認する。

## 完成面子候補の列挙を読む

次の実例は、`MentsuCandidate.candidates` と `MentsuCandidate.mem_candidates` である。

読む前に知る語彙:

- `inductive`
- `namespace`
- `theorem`
- `cases`
- `rcases`
- `simp`
- `left`
- `refine`
- `?_`
- `exact`
- `∈`

`MentsuCandidate` は、通常形で完成面子として扱う候補を、順子または刻子として表す。
`MentsuCandidate.candidates` は、実行用に全順子候補と全刻子候補を並べたリストである。
`MentsuCandidate.mem_candidates` は、任意の完成面子候補がそのリストに含まれることを確認する。

この定理は、後で完成面子候補を列挙して探索するとき、列挙リストに取りこぼしがないことを支える。
刻子の場合には、すでに読んだ `Tile.mem_all` が使われる。

## 字牌を含む候補が順子ではないことを読む

次の実例は、`MentsuCandidate.IsShuntsu` と `MentsuCandidate.honor_not_in_shuntsu` である。

読む前に知る語彙:

- `Prop`
- `theorem`
- `∈`
- `¬`
- `cases`
- `simp`
- `at`

`MentsuCandidate.IsShuntsu` は、完成面子候補が順子であることを表す述語である。
`honor_not_in_shuntsu` は、字牌を含む完成面子候補が順子ではないことを確認する。

麻雀上、順子は同じスートの連続する数牌だけからなる。Lean上では、`Shuntsu.tiles` が数牌だけを返すため、
字牌が含まれるという仮定と両立しないことを `simp` で確認している。

## 雀頭と完成面子を同じ和了構成部品として読む

次のまとまりは、`WinningComponent` と `WinningComponent.tiles` である。

先に [domain-vocabulary.md](domain-vocabulary.md) の「和了構成部品」を読む。

読む前に知る語彙:

- 直和 `⊕`
- `.inl`
- `.inr`
- `def`
- `instance`
- `example`

通常形の和了分割では、雀頭と完成面子をどちらも完成した部品として並べて扱う。
`WinningComponent` は、雀頭 `Toitsu` または完成面子候補 `MentsuCandidate` のどちらかを持つ型である。

- `WinningComponent.pair`: 雀頭を和了構成部品として作る。
- `WinningComponent.shuntsu`: 順子を和了構成部品として作る。
- `WinningComponent.koutsu`: 刻子を和了構成部品として作る。
- `WinningComponent.tiles`: 和了構成部品を構成する牌種列を返す。

ここでも `Tile.format .mpsz` を使った `example` により、雀頭 `55m`、順子 `456p`、刻子 `777z` を確認する。

## 和了構成部品の整列キーが情報を失わないことを読む

次の実例は、`WaitCompletion.lean` の `WinningComponent.orderKey` と `WinningComponent.orderKey_injective` である。

読む前に知る語彙:

- `Nat`
- `Function.Injective`
- `native_decide`

和了分割では、同じ和了構成部品が異なる順番で並ぶことがある。後続処理で順番の違いをなくすため、
`WinningComponent.orderKey` は雀頭、順子、刻子を自然数へ写し、その数値順で並べられるようにする。

3種類の和了構成部品には互いに重ならない数値範囲を使う。雀頭の範囲の後に全順子、その後に全刻子を置き、
各範囲内では牌種、スート、順子の開始位置を使って区別する。ソース中の `example` は、雀頭 `55m`、
順子 `456p`、刻子 `111z` がそれぞれ異なる範囲のキー `4`、`44`、`82` を持つことを確認する。

`orderKey_injective` は、キーが等しい2つの和了構成部品は元から等しいことを保証する。
したがって、整列のために数値キーを使っても、異なる和了構成部品が同じものとして扱われることはない。
証明は、有限個の `WinningComponent` の全組合せを `native_decide` で計算して確認する。

## 和了構成部品列を標準順で表す

次の実例は、`WaitCompletion.lean` の `WinningComponent.canonicalize`、
`CanonicalWinningComponents`、`WinningComponent.canonicalize_eq_of_perm` である。

先に [domain-vocabulary.md](domain-vocabulary.md) の「和了構成部品列の標準順表現」を読む。

読む前に知る語彙:

- `List.Perm`
- `structure`
- `mergeSort`
- `apply`
- `intro`
- `simpa` と `using`
- `omega`
- `.trans` と `.symm`
- `exact`

同じ和了分割でも、探索過程によって雀頭や面子が異なる順番で列に入ることがある。
`canonicalize` は、前節で読んだ `orderKey` の昇順に和了構成部品を並べ、入力時の順番の違いをなくす。
整列は部品を追加・削除しないため、各部品とその個数はそのまま残る。

ここで標準化される対象は `WinningComponent` 単体ではなく、和了分割を表す `List WinningComponent` である。
また、同一視するのはリスト上の順番だけであり、異なる分割や牌姿を同じものにする処理ではない。
`canonicalize` 単体の返り値は通常のリストだが、公開結果では `CanonicalWinningComponents` が
リスト本体と標準順であることの証拠をまとめて持つ。

ソース中の `example` は、雀頭 `55m` と順子 `456p` の順番を入れ替えた2つの列が、
標準順へ変換した後には同じ列になることを計算で確認する。

`CanonicalWinningComponents.ofList` は、任意の和了構成部品列を標準順へ変換し、証拠付きの値として包む。
`WaitCompletion.winningComponents` はこの型なので、Finderが外部へ返す和了分割は型の時点で標準順である。
待ち分解の生成のように通常のリスト処理へ渡す場面では、`CanonicalWinningComponents.toList` で本体を取り出す。

`canonicalize_eq_of_perm` は、この具体例を任意の和了構成部品列へ一般化する。
仮定 `first.Perm second` は、2つの列が同じ要素を同じ個数だけ持ち、順番だけが異なり得ることを表す。
証明は、両方の結果がキー順に整列済みであることと、整列前後で要素と個数が変わらないことを使う。
さらに `orderKey_injective` がキーの衝突を除外するため、2つの整列結果は要素ごとに一致する。

これにより、後続の待ち分解生成は、和了分割の部品が偶然どの順番で発見されたかに影響されず、
含まれる和了構成部品とその個数に基づいて比較できる。

## 牌種列から指定した枚数だけ取り除く

次の実例は、`WaitCompletionFinder.lean` の `removeTiles` と `removeTiles_append_left` である。

読む前に知る語彙:

- `List Tile`
- `Option`
- `List.erase`
- `++`
- `induction`
- `nil` と `cons`
- `rfl`
- `simp`

`removeTiles available wanted` は、利用可能な牌種列 `available` から、必要な牌種列 `wanted` を
1枚ずつ取り除く。すべて取り除ければ残りを `some` で返し、途中で必要な牌がなければ `none` を返す。
ここで扱うのは集合ではなくリストなので、同じ牌種の出現回数が区別される。

ソース中の `example` では、利用可能な牌列を `55m 1p`、除去対象を `5m` とする。
`removeTiles` は `5m` を1枚だけ除くため、もう1枚の `5m` と `1p` が残る。

`removeTiles_append_left` は、利用可能な牌列を `wanted ++ remaining` として作れば、`wanted` の除去が
必ず成功して `remaining` をそのまま返すことを保証する。この定理が直接扱うのは、この連結順で作った入力である。
入力順一般に対する成功条件は、直前の `exists_removeTiles_eq_some_iff_perm` が順列を使って別に特徴づけている。

証明は `wanted` の長さに沿った帰納法で読む。空なら何も除かない。先頭牌がある場合はその1枚を除き、
残りの牌列について帰納法の仮定を使う。この保証により、後続の分割探索は、候補の牌を元の牌列へ
連結して作った場合に、その候補を確実に取り戻せる。

## 雀頭候補の列挙に過不足がないことを読む

次の実例は、`WaitCompletionFinder.lean` の `pairComponentCandidates`、
`pair_mem_pairComponentCandidates`、`pair_of_mem_pairComponentCandidates` である。

読む前に知る語彙:

- `map`
- `∈`
- `∃`
- `rcases`
- `obtain`
- `List.mem_map`
- `simp`
- `exact`
- `rfl`

和了分割の探索では、34種類の牌種それぞれについて、その牌種2枚を雀頭とする候補を試す。
`pairComponentCandidates` は `Tile.all` の各牌種を `WinningComponent.pair` で雀頭の和了構成部品へ変換したリストである。
ソース中の `example` は、赤牌の雀頭もこの候補列に含まれることを計算で確認する。

候補列挙には、必要な候補を取りこぼさない完全性と、余計な種類を混ぜない健全性の両方が必要になる。

- `pair_mem_pairComponentCandidates`: 任意の雀頭が候補列に含まれるため、雀頭を取りこぼさない。
- `pair_of_mem_pairComponentCandidates`: 候補列の各要素は何らかの雀頭なので、順子や刻子が混ざらない。

完全性の証明は、雀頭を構成する牌種が `Tile.all` に含まれるという、先に読んだ `Tile.mem_all` を使う。
健全性の証明は、候補が `map` 元のどの牌種から作られたかを取り出し、その牌種の対子を存在例として返す。
この2定理を合わせると、後続の和了分割探索が調べる雀頭候補は、全雀頭とちょうど一致する。

## 完成面子候補を直接列挙する

面子分解では、`Pattern.lean` が提供する `MentsuCandidate.candidates` を直接使う。
この段階の値は順子または刻子であることが型によって保証されるため、雀頭も持てる
`WinningComponent` へ包んだ候補列や、雀頭が混ざらないことを示す追加の証明は必要ない。

`WinningComponent` への変換は、雀頭と面子をまとめて通常和了分割を作る境界でだけ行う。

## 牌種列を指定個数の完成面子へ分解する

次の実例は、`WaitCompletionFinder.lean` の `decomposeMentsu` である。

読む前に知る語彙:

- `fuel`
- `fuel + 1`
- `List (List MentsuCandidate)`
- `List.flatten`
- `map`
- `match`
- `[]` と `::`

`decomposeMentsu fuel tiles` は、牌種列全体をちょうど `fuel` 個の順子・刻子へ分解する方法を列挙する。
`fuel` は「最大で何個まで試すか」ではなく、求める完成面子の個数である。

返り値の外側のリストは、異なる分解方法の列である。各内側の `List MentsuCandidate` が、
1つの分解を構成する完成面子列になる。したがって、次の2つは意味が異なる。

- `[]`: 条件を満たす分解方法が1つもない。
- `[[]]`: 完成面子を0個使う空の分解が1通りある。

`fuel = 0` の場合、入力牌列も空なら `[[]]`、牌が1枚でも残っていれば `[]` を返す。
ソース中の2つの `example` は、この基底ケースの違いを `rfl` で確認する。

`fuel + 1` の場合は、`MentsuCandidate.candidates` から最初の完成面子を1つずつ試す。
その牌を `removeTiles` で除けた枝だけについて、残りの牌をちょうど `fuel` 個へ再帰的に分解する。
各候補から得た分解列を `List.flatten` で1つにつなぐため、可能な分解を1つに決めず、すべて返す。

この列挙の意味は `MentsuPartitionSpec` が、面子列の長さと、面子を牌へ戻した列の入力に対する
`List.Perm` だけで表す。`mem_decomposeMentsu_iff_spec` は、列挙所属とこの外延仕様を直接結ぶ。

証明は `fuel` に対する帰納法で、健全性方向では先頭面子の除去結果と残りの牌保存則を合成する。
完全性方向では全体の牌保存則から先頭面子を除ける結果を取り出し、残りへ帰納法の仮定を適用する。
除去順を保存する別の操作履歴型は使わない。

## 通常和了分割の実行器と外延仕様の一致を読む

次の実例は、`WaitCompletionFinder.lean` の `winningPartitions`、`WinningPartitionSpec`、
`mem_winningPartitions_iff_spec` である。

`winningPartitions tiles` は、雀頭候補を除いた残りを `decomposeMentsu` で分解し、雀頭と面子を
`WinningComponent` の列へまとめる実行器である。`WinningPartitionSpec` は同じ結果を、雀頭、
`List MentsuCandidate`、全部品の牌列と入力の `List.Perm` だけで表す。

`mem_winningPartitions_iff_spec` は列挙所属とこの外延仕様を直接結ぶ。健全性方向では雀頭の除去結果と
`MentsuPartitionSpec.tiles_perm` を合成する。完全性方向では全体の順列から雀頭を除ける結果を取り出し、
残りを `mem_decomposeMentsu_iff_spec` で面子列挙へ戻す。

入力順を変える場合は `WinningPartitionSpec.of_perm` が牌保存則へ新しい順列を合成する。
上位層には除去順を記録する別の操作履歴型を置かず、この外延仕様を通常和了分割の唯一の意味表現として使う。

## 待ち牌の実行器と宣言的仕様の一致を読む

次の実例は、`WaitCompletionFinder.lean` の `IsLegalTenpaiHand`、`IsWaitFor`、`waitingTiles`、
`mem_waitingTiles_iff`、`waitingTiles_ne_nil_iff` である。

読む前に知る語彙:

- `Prop`
- `Bool`
- `∧`
- `List.filter`
- `↔`
- 健全性と完全性
- `by_cases`
- `obtain`
- `rintro`
- `simp`
- `Bool.and_eq_true`

`IsLegalTenpaiHand tiles` は、待ち判定へ渡す手牌の事前条件をまとめる。通常形聴牌として扱う枚数が
1、4、7、10、13枚のいずれかであり、各牌種が物理的な上限の4枚を超えないことを要求する。

`IsWaitFor tiles candidate` は、候補牌が手牌 `tiles` の通常形待ちであるという宣言的仕様であり、
次の3条件を同時に要求する。

- 元の手牌が `IsLegalTenpaiHand` を満たす。
- 候補牌が手牌中に4枚未満しかなく、加牌しても5枚目にならない。
- 候補牌を先頭へ1枚加えた牌列が、雀頭1つと完成面子列からなる通常形で和了する。

`waitingTiles tiles` は同じ条件を計算する実行器である。まず合法手牌でなければ空列を返す。
合法なら全牌種 `Tile.all` を、4枚未満であることと加牌後に `isWinning` が真になることのBool論理積で
`filter` する。

`mem_waitingTiles_iff` は、候補牌がこの実行結果に含まれることと `IsWaitFor` を満たすことが同値だと示す。
したがって、列挙された牌が実際の通常形待ちであるという健全性と、仕様を満たす待ち牌を列挙が
取りこぼさないという完全性の両方が得られる。

証明は `by_cases legal : IsLegalTenpaiHand tiles` で、事前条件を満たす場合と満たさない場合に分ける。
非合法なら実行器は空列を返し、仕様の最初の条件も偽なので両辺は成立しない。

合法な場合は、`waitingTiles` と `IsWaitFor` の定義を `simp` で展開する。任意の牌種が `Tile.all` に
含まれることは `Tile.mem_all` で消え、`Bool.and_eq_true` が実行器の `&&` を2つの命題へ分解する。
残る条件は「4枚未満」と「加牌後に通常形で和了する」であり、`IsWaitFor` の残り2条件と一致する。

`IsWaitFor.of_perm` は、牌姿リストを並べ替えても同じ候補牌が待ちであり続けることを示す。
`IsWaitFor` が要求する合法な手牌枚数は順列の `length_eq` で、各牌種の合法枚数と候補牌の残り枚数は
`permutation.count` で移せる。これらは、順列が要素数と各要素の重複数を保存することの直接的な利用である。

加牌後の通常和了だけは `isWinning` というBool計算で表されているため、順列保存則を直接適用できない。
そこで、まず `winningPartitions` が空でないことへ読み替えて分割を1つ取り出し、
`mem_winningPartitions_iff_spec` の `.mp` で宣言的な `WinningPartitionSpec` の証拠へ変える。
手牌間の順列の両側へ同じ候補牌を加えた `permutation.cons candidate` を
`WinningPartitionSpec.of_perm` に渡せば、並べ替え後にも同じ分割を移せる。最後に同値定理の `.mpr` で
列挙結果への所属へ戻し、結果が空でないことから `IsStandardAgari` を復元する。

この往復は、入力順に依存しないという意味論上の性質を `WinningPartitionSpec` が担当し、
`isWinning` はその証拠を探索する実行器として使われていることを表す。ソース中の例は、
「東・東・東・赤」で赤待ちであることを具体計算し、その証拠を「赤・東・東・東」へ移す。

ソース中の例は、赤牌1枚の手牌について赤牌自身が単騎待ちとして `waitingTiles` に含まれることを示す。
同値定理の `.mpr` で目標を `IsWaitFor` へ変換し、具体的な有限計算を `native_decide` で確認する。
`unfold` は、この具体例で判定手続きが見えるように宣言的仕様を展開するために使っている。

`IsTenpai tiles` は、`IsWaitFor tiles candidate` を満たす牌種 `candidate` が少なくとも1つ存在するという、
牌姿全体の宣言的な聴牌仕様である。`waitingTiles_ne_nil_iff` は、待ち牌列挙の結果が空でないことと
`IsTenpai tiles` が同値だと示す。前の定理が個々の候補牌について健全性と完全性を保証したのに対し、
この定理はそれを「待ち牌が存在するか」という手牌単位の判定へ集約する。

左から右へは、空でない `waitingTiles tiles` から `List.exists_mem_of_ne_nil` で候補牌を1つ取り出し、
`mem_waitingTiles_iff` の `.mp` でその所属証拠を `IsWaitFor` の証拠へ変換する。右から左へは、
`IsTenpai` が持つ候補牌と待ちの証拠を `rintro` で取り出し、同値定理の `.mpr` で列挙結果への所属を得る。
列挙結果が空だと仮定するとその牌は所属できないため、矛盾する。

続く例は、赤牌1枚の手牌が意味論上も聴牌であることを確認する。ここでは具体的な列挙への所属を
`native_decide` で計算し、`List.ne_nil_of_mem` で列挙結果が空でないことへ変え、
`waitingTiles_ne_nil_iff` によって `IsTenpai` の証明として受け取る。この流れにより、有限な実行結果が
宣言的な聴牌仕様の証拠になることを小さな入力で確かめられる。

## 待ちと和了分割を返すFinderの正しさを読む

次の実例は、`WaitCompletionFinder.lean` の `findWaitCompletions`、`CompletionFor`、
`mem_findWaitCompletions_iff` である。

読む前に知る語彙:

- `List.flatMap`
- `List.map`
- `List.dedup`
- `List.mem_dedup`
- `List.mem_flatMap`
- `List.mem_map`
- 添字付き帰納型
- 健全性と完全性
- `obtain`
- `cases`
- `refine`

`findWaitCompletions tiles` は、単に待ち牌だけでなく、その牌を加えたときの通常和了分割も返す実行器である。
まず `waitingTiles tiles` の各待ち牌について `winningPartitions` を実行し、待ち牌と分割を
`WaitCompletion` にまとめる。分割内の部品順を `WinningComponent.canonicalize` で標準化し、最後に `dedup` で
同じ結果の重複を除く。

`CompletionFor tiles completion` は、返り値 `completion` の宣言的仕様である。その証拠は、
`IsWaitFor tiles wait` を満たす待ち牌と、加牌後の牌列に対する `WinningPartitionSpec` を持つ。
一方、返り値に記録される分割は正規化済みであるため、仕様は正規化前の `rawComponents` が存在し、
`completion.winningComponents` がその標準順表現になるという形を帰納型の結論で表している。

`CompletionFor.of_perm` は、入力牌姿を並べ替えても同じ `completion` の証拠を移せることを保証する。
証拠を `cases` で分解すると、待ち牌の正しさ `IsWaitFor` と加牌後の分割 `WinningPartitionSpec` が得られる。
前者は `IsWaitFor.of_perm` で移し、後者は `WinningPartitionSpec.of_perm` で移す。分割側の入力には待ち牌が
1枚加わっているため、`permutation.cons wait` により元の順列の両側へ同じ牌を加えてから渡す。

この定理は、下位で確認した二つの順列不変性を `CompletionFor` というFinder仕様の水準で合成する。
返り値の待ち牌と正規化済み分割は変更せず、入力との関係を示す証拠だけを移すため、Finderの意味論が
牌の入力順ではなく牌種ごとの枚数に依存することが分かる。ソース中の例は、「赤・東・東・東」に対する
任意の正しいCompletion証拠を、「東・赤・東・東」へ移せることを確認する。二つの列が順列であることは
有限な具体値なので `native_decide` で検査している。

`mem_findWaitCompletions_iff` は、Finderの結果への所属と `CompletionFor` が同値だと示す。
これは `mem_waitingTiles_iff` と `mem_winningPartitions_iff_spec` という二つの下位境界を合成した、
探索全体の健全性・完全性である。Finderが返した組には正しい待ち牌と和了分割が必ずあり、逆に、
仕様を満たす組はFinderの結果に必ず含まれる。

証明冒頭の `rw [findWaitCompletions, List.mem_dedup]` は実行器を展開し、重複除去後への所属を
重複除去前への所属に直す。健全性方向では、`List.mem_flatMap.mp` が結果を生成した待ち牌を、
もう一度の `List.mem_flatMap.mp` が正規化前の分割を取り出す。それぞれの所属を下位の同値定理の `.mp` で
`IsWaitFor` と `WinningPartitionSpec` へ変換し、`CompletionFor.intro` に渡す。

完全性方向では `cases valid` により仕様の証拠から待ち牌、分割、二つの正しさの証拠を取り出す。
下位定理の `.mpr` でそれらを実行結果への所属へ戻し、`List.mem_map.mpr` と
`List.mem_flatMap.mpr` を使ってFinder全体への所属を組み立てる。両方向で同じ二つの境界定理を
逆向きに使う構造が、過不足のなさを直接表している。

ソース中の例は、赤牌1枚の単騎待ちについて、赤牌を加えた対子分割を持つ `WaitCompletion` が
`CompletionFor` を満たすことを示す。Finderの出力全体が期待する1要素列と等しいことを
`native_decide` で計算し、その等式で所属目標を書き換える。最後に同値定理の `.mp` によって、
計算で得た所属を宣言的な正しさの証拠へ変換する。

## 宣言的な聴牌仕様を計算で判定する

次の短い実例は、`WaitCompletionFinder.lean` の `decidableIsTenpai` である。

読む前に知る語彙:

- `Prop`
- `Decidable`
- `instance`
- `rw`
- `infer_instance`
- `decide`

`IsTenpai tiles` は「`IsWaitFor tiles candidate` を満たす牌種が存在する」という宣言的な命題である。
命題として意味を記述するだけなら十分だが、プログラムがその真偽で分岐したり、具体的な手牌を
`decide` で評価したりするには `Decidable (IsTenpai tiles)`、つまり判定手続きが必要になる。

`decidableIsTenpai` は、新しい探索処理を別に実装するのではなく、すでに正しさを示した
`waitingTiles` を判定手続きとして再利用する。証明中の `rw [← waitingTiles_ne_nil_iff]` は、
求める `Decidable (IsTenpai tiles)` を `Decidable (waitingTiles tiles ≠ [])` へ置き換える。
後者は具体的なリストが空かどうかの判定なので、`infer_instance` がLean標準の手続きを見つけられる。

`instance` として登録されるため、利用側はこの変換を毎回指定する必要がない。
`decide (IsTenpai tiles)` と書けば、Leanが `decidableIsTenpai` を自動的に選び、`waitingTiles` の計算を
通してBool値を返す。ソース中の二つの例は、赤牌1枚が単騎聴牌として `true`、空手牌が合法な
通常形聴牌ではないため `false` になることを `native_decide` で確認する。

## 可約性の計算と意味の一致を読む

次の実例は、`WaitDecompositionCode.lean` の `reducibility`、`determineReducibility`、`reducibility_eq_reducible_iff`、
`reducibility_eq_irreducible_iff` である。

先に [domain-vocabulary.md](domain-vocabulary.md) の「待ち核集合」と「可約と既約」を読む。

読む前に知る語彙:

- `def`
- `if`
- 証拠付き `if`
- `Option`
- `theorem`
- `↔`
- `¬`
- `simp`

`reducibility` は、聴牌であることが確認済みの牌列について、待ち核集合を変えずに完成面子を除去できるかを調べる。
除去できれば `reducible`、できなければ `irreducible` を返す。

`determineReducibility` は、聴牌かまだ分からない一般の牌列に対する入口である。
聴牌なら条件分岐で得た証拠を `reducibility` へ渡して結果を `some` に包み、非聴牌なら `none` を返す。
したがって `none` は解析失敗や既約を意味するのではなく、可約性を分類する前提である聴牌を満たさないことを表す。

`reducibility_eq_reducible_iff` は、計算結果が `reducible` であることと、実際に待ち核集合を保つ面子除去が
可能であることが同値だと保証する。左から右は誤って可約と判定しないこと、右から左は可能な面子除去を
見落とさないことに対応する。

証明の `simp [reducibility]` は、`reducibility` の条件分岐を展開し、その判定条件が右辺の
`canReduceMentsuPreservingWaitCores tiles = true` と一致することを確認する。

`reducibility_eq_irreducible_iff` は対になる保証で、計算結果が `irreducible` であることを、待ち核集合を
保ったまま除去できる完成面子がないこととして特徴づける。既約性のために別の探索をするのではなく、
同じBool判定が `false` であることを使っている点を読む。

## 待ち分解から核成分列を分離する処理を読む

次の実例は、`WaitDecompositionCode.lean` の `WaitDecomposition`、`WaitCoreExtraction`、
`extractWaitCore` である。

先に [domain-vocabulary.md](domain-vocabulary.md) の「待ち分解」と「待ち核」を読む。

読む前に知る語彙:

- `structure`
- `filter`
- `fun`
- `!`

`WaitDecomposition` は、1つの待ち牌と、待ち牌を除いた和了分割に見える具体牌付き部品列を持つ。
この段階では、不完全部品と、すでに完成している順子・刻子が同じ `components` に並んでいる。

`extractWaitCore` は、順子と刻子を `removedMentsu` に分離し、それ以外を `core` に残して
`WaitCoreExtraction` を作る。2つの `filter` は同じ部品列を反対の条件で選別しており、
待ち牌と各部品の具体牌は変更しない。

最初は、待ち牌 `4m` に対して、部品列が「単騎 `4m`、完成順子 `123p`」である1つの待ち分解だけを考える。
`extractWaitCore` を適用すると、単騎 `4m` は `core` に残り、完成順子 `123p` は `removedMentsu` に入る。
スートが異なるため別の分解を考える必要がなく、ここでは2つの `filter` による振り分けだけを読めばよい。

`extractWaitCore` 自体は1つの待ち分解から完成面子を分離する局所処理であり、
牌姿全体が可約か既約かは判定しない。牌姿全体の判定では、そこから得られる待ち核集合を、完成面子除去の
前後で比較する必要がある。複数の分解を持つ `1234m` は、その段階で扱う例である。

## 分離結果から待ち核集合を作る処理を読む

次の実例は、`WaitDecompositionCode.lean` の `WaitCore` と `waitCores` である。

先に [domain-vocabulary.md](domain-vocabulary.md) の「待ち核」と「待ち核集合」を読む。

読む前に知る語彙:

- `map`
- `fun`
- `|>`
- `List`

`waitCores` は、発見済みの全待ち分解から `WaitCoreExtraction` を作り、それぞれを `WaitCore` に変換する。
この変換では、待ち牌 `wait` と核成分列 `core` を残し、どの完成面子を分離したかを表す `removedMentsu` は忘れる。
これにより、異なる和了分割から同じ待ち牌と核成分列が得られた場合、それらを同じ待ち核として比較できる。

前節の「単騎 `4m`、完成順子 `123p`」という待ち分解なら、待ち核には待ち牌 `4m` と単騎 `4m` だけが残り、
分離した順子 `123p` は含まれない。

最後の `deduplicateAndSortBy` は、同じ待ち核の重複を除き、一定の順序に整列する。
したがって返り値の型は `List WaitCore` だが、コード上では重複を除いて整列したリストを有限の待ち核集合として使う。

## 待ち核集合を保つ面子除去を読む

次の実例は、`WaitDecompositionCode.lean` の `canReduceMentsuPreservingWaitCores` である。

先に [domain-vocabulary.md](domain-vocabulary.md) の「待ち核集合」と「可約と既約」を読む。

読む前に知る語彙:

- `Bool`
- `&&`
- `!`
- `List.any`
- `==`

`mentsuReductions tiles` は、牌列から完成面子を1つ取り除いて得られる候補を列挙する。
`canReduceMentsuPreservingWaitCores` は、その候補の中に次の2条件を両方満たすものがあるかを調べる。

- 除去後の牌列にも待ち牌があり、聴牌形として残っている。
- 除去前後で `findWaitCores` が返す待ち核集合が一致する。

除去後の聴牌を別に確認するため、待ちのない牌列どうしで空の待ち核集合が一致しただけでは可約にならない。
また、`1 < tiles.length` により、完成面子を含み得ない1枚単騎は最初に除外する。

結果が `true` なら、元の牌姿には待ち核集合を変えずに分離できる完成面子が少なくとも1つある。
どの候補が成功したかではなく、そのような候補が存在するかだけを返す判定である。

`canReduceMentsuPreservingWaitCores` は、実際に実行して `true` または `false` を返す唯一の可約性判定である。
`reducibility` はこのBoolを直接 `if` の条件に使う。後続の同値定理では、判定が `true` または `false` であることを
それぞれ可約・既約という分類結果に対応させる。

## 和了構成部品から待ち牌を除いた形を読む

次の実例は、`WaitDecompositionCode.lean` の `componentKindAfterRemovingWait` と `componentAfterRemovingWait` である。

先に [domain-vocabulary.md](domain-vocabulary.md) の「和了構成部品」を読む。

読む前に知る語彙:

- `Option`
- `match`
- `if`
- `==`
- `!=`
- `Option.map`
- `List.erase`
- `example`
- `rfl`

この関数は、1つの和了構成部品 `WinningComponent` と指定した待ち牌を受け取り、その牌を1枚除いたときに見える
不完全部品の種別を返す。最初は次の単純な対応を読む。

- 対子 `55m` から `5m` を除くと、単騎 `5m` が残る。
- 刻子 `777p` から `7p` を除くと、対子 `77p` が残る。

順子では、除く牌の位置によって残るターツが変わる。

- 順子 `234s` から `2s` を除くと `34s` が残り、両面になる。
- 順子 `234s` から `3s` を除くと `24s` が残り、嵌張になる。
- 順子 `123s` から `3s` を除くと `12s` が残り、辺張になる。

ソース中の `example` は、この5つの対応をLeanの計算で確認する。
指定牌が対子・刻子と同じ牌種でない場合、または順子とスートやランクが合わない場合は `none` を返す。
ここでの `none` は待ち全体が存在しないという意味ではなく、この1つの和了構成部品から指定牌を除く形を作れないという意味である。

`componentAfterRemovingWait` は、その種別判定に具体的な牌の除去を加える。
種別が得られた場合だけ `List.erase` で待ち牌を最初の1枚だけ除き、種別と残った牌種列を
`WaitComponent` にまとめる。種別が `none` なら、`Option.map` により結果も `none` のままになる。

対子 `55m` と待ち牌 `5m` の例では、種別は単騎、残った牌種列は `[5m]` になる。
この対応もソース中の `example` が `rfl` で確認している。

## 和了分割から待ち分解を列挙する処理を読む

次の実例は、`WaitDecompositionCode.lean` の `componentDecompositions` である。

先に [domain-vocabulary.md](domain-vocabulary.md) の「和了構成部品」と「待ち分解」を読む。

読む前に知る語彙:

- `let rec`
- `match`
- `[]`
- `::`
- `map`

`WaitCompletion` は、1つの待ち牌と、その牌を加えた和了分割を持つ。
`componentDecompositions` は分割の和了構成部品を先頭から調べ、待ち牌を除ける部品を1つ選んで不完全部品へ変える。
選ばなかった部品は、対子・順子・刻子という完成した種別のまま待ち分解に残す。

最初は、待ち牌が `5m`、和了分割が雀頭 `55m` と順子 `123p` からなる例を読む。
待ち牌を除けるのは雀頭だけなので、結果は「単騎 `5m`、完成順子 `123p`」という1つの待ち分解になる。
ソース中の `example` は、この列挙結果を `rfl` で確認する。

同じ待ち牌を除ける和了構成部品が複数ある場合は、どの部品を除去元として選ぶかごとに別の待ち分解を返す。
つまり、この処理は1つの分割を決め打ちで読むのではなく、その分割から生じるすべての観測結果を列挙する。

## 複数の和了分割から具体的な待ち分解をまとめる

次の実例は、`WaitDecompositionCode.lean` の `waitDecompositions` である。

読む前に知る語彙:

- `let`
- `flatMap`
- `map`
- `structure`

`waitDecompositions` は、複数の `WaitCompletion` に前節の `componentDecompositions` を適用し、すべての結果を
待ち牌と具体牌付き部品列を持つ `WaitDecomposition` にまとめる。

和了分割は、同じ部品を異なる順序で持つことがある。そのままでは部品順だけが異なる待ち分解が別物に見えるため、
各待ち分解の部品列を `canonicalizeWaitDecomposition` で一定の順序に並べる。最後に
`deduplicateAndSortBy` が同一待ち分解の重複を除き、結果全体も一定の順序へ整える。

ソース中の `example` は、雀頭 `55m` と順子 `123p` の順序だけを入れ替えた2つのcompletionを入力する。
どちらからも同じ「単騎 `5m`、完成順子 `123p`」が得られるため、部品順を整列して重複を除いた結果は1件だけになる。
これにより、データ上の部品順や重複ではなく、観測される待ち牌と部品の内容を比較できる。

## 具体牌を忘れて種別だけの待ち分解を作る

次の実例は、`WaitDecompositionCode.lean` の `WaitKindDecomposition` と `waitKindDecompositions` である。

先に [domain-vocabulary.md](domain-vocabulary.md) の「待ち分解」を読む。

読む前に知る語彙:

- `map`
- `fun`
- `|>`

`waitKindDecompositions` は、各 `WaitDecomposition` の待ち牌を保持したまま、具体牌付き部品を
その部品種別 `kind` だけに変換する。単騎がどの牌だったか、完成順子がどのスート・ランクだったかは忘れるが、
待ち牌と「単騎、順子」のような部品種別列は残る。

ソース中の `example` では、待ち牌がどちらも `5m` で、完成順子だけが `123p` と `456p` で異なる
2つの具体的な待ち分解を作る。具体牌を忘れると、どちらも部品種別列 `[tanki, shuntsu]` になるため、
重複排除後の `WaitKindDecomposition` は1件になる。

この段階では部品種別列を数値へ変換しない。次の `waitDecompositionCodeEntries` が、種別だけの待ち分解を
待ち牌と素数積コードの組へ変換する。

## 種別だけの待ち分解を素数積コードへ変換する

次の実例は、`WaitDecompositionCode.lean` の `WaitComponentKind.prime`、`componentProduct`、
`WaitDecompositionCodeEntry`、`waitDecompositionCodeEntries` である。

先に [domain-vocabulary.md](domain-vocabulary.md) の「待ち分解コード」を読む。

読む前に知る語彙:

- `Nat`
- `List.foldl`
- `map`
- `|>`

各部品種別には異なる素数が割り当てられている。たとえば単騎は2、順子は13である。
`componentProduct` は1から始めて、種別だけの待ち分解の各部品に対応する素数を順に掛ける。

積では掛ける順序が結果に影響しないため、部品列の順序は忘れられる。一方、同じ部品が複数あれば
同じ素数を繰り返し掛けるため、その個数は指数として残る。たとえば `[tanki, shuntsu]` は
$2 \times 13 = 26$、`[tanki, shuntsu, shuntsu]` は $2 \times 13^2 = 338$ になる。

`waitDecompositionCodeEntries` は、計算したコードだけでなく待ち牌も `WaitDecompositionCodeEntry` に残す。
ソース中の `example` は、待ち牌 `5m` と部品種別 `[tanki, shuntsu]` から
`{ wait := 5m, code := 26 }` が得られることを計算で確認する。

## 待ち牌を忘れてコードの種類だけを取り出す

次の実例は、`WaitDecompositionCode.lean` の `waitDecompositionCodes` である。

先に [domain-vocabulary.md](domain-vocabulary.md) の「待ち分解コード」を読む。

読む前に知る語彙:

- `map`
- `|>`

`waitDecompositionCodes` は、待ち牌付きの各entryから `code` だけを取り出す。
この変換後は待ち牌の対応自体は失われるが、異なる待ち牌から同じコードが得られた場合の出現回数は保持し、
コード値の昇順に整列する。同じ待ち牌とコードの組に対する重複は、entryを作る段階で除かれている。

ソース中の `example` では、待ち牌 `5m` と `6m` がそれぞれ単騎と完成順子からなる待ち分解を持つ。
待ち牌は異なるが、どちらの部品種別列も `[tanki, shuntsu]` なのでコードは26であり、結果は `[26]` になる。

この表現は、コード系列の中で最も多くの情報を忘れている。
コード列が一致しても、待ち牌、具体的な部品の牌、元の牌姿が同じとは限らない。
同じコードが複数回現れることは、そのコードに対応する異なる待ち牌付きentryが複数あることを示す。
ただし、コード列だけから各コードに対応する待ち牌を復元することはできない。

## 直接生成器が妥当なSeedを過不足なく返すことを読む

次の実例は、`DirectWaitGeneration.lean` の `seedCandidates`、`directSeeds`、`directSeeds_sound`、
`directSeeds_complete`、`mem_directSeeds_iff` である。

読む前に知る語彙:

- `Seed.valid`
- `List.filter`
- `List.mem_filter`
- `List.flatMap`
- `List.mem_flatMap`
- `List.map`
- `List.mem_map`
- `List.dedup`
- `List.mem_dedup`
- 健全性と完全性

直接生成は、完成済みの形から待ち牌を1枚取り除く向きに待ち導出の生成元を作る。
`seedCandidates n` は、雀頭と `n` 個の面子からなる全完成形、待ち牌を取り除く全部品位置、
選択した部品に実際に含まれる牌種、という3段階を列挙する。全34牌種を各部品で試さず、候補を
部品内の最大3牌種へ限定することで、大きな不要探索を避けている。

候補であるだけでは、同じ牌種を5枚使う完成形や、面子順・同一面子の選択位置だけが違う重複を含み得る。
`directSeeds n` は `seedCandidates n` を `Seed.valid` でフィルタし、物理的な4枚制限と二つの正規化条件を
満たすSeedだけを残す。

`directSeeds_sound` は、生成結果への所属から `List.mem_filter.mp` でフィルタ条件を取り出す。
したがって、生成器が返したSeedは必ず `Seed.valid` を満たし、不正な待ち導出の生成元が混ざらない。
これが健全性である。

`directSeeds_complete` は逆に、任意の妥当なSeedが候補生成の3段階を通ることを示す。
全完成形と全部品位置への所属は `mem_winningShapes` と `mem_componentIndices` が保証する。
残る待ち牌について、`Seed.valid` の最初の条件は、選択部品からその牌を除くと不完全形が得られることを表す。
`wait_mem_component_of_componentKind_isSome` は、この成功条件から待ち牌が選択部品に含まれることを導く。
その所属を `dedup` と `map`、さらに外側の二つの `flatMap` へ戻せば、Seedが `seedCandidates` に含まれる。
最後に妥当性証拠をフィルタへ渡すため、正しいSeedは取りこぼされない。これが完全性である。

`mem_directSeeds_iff` はこの二方向を組にし、直接生成器への所属と `Seed.valid` が同値だと述べる。
候補削減が結果の意味を変えないことを、実行器と仕様の一致として利用できる形である。

ソース中の例は、面子を持たない赤牌対子だけの完成形を作り、雀頭から赤牌を除く単騎Seedが
`directSeeds 0` に含まれることを示す。`Seed.valid` は具体的な有限計算として `native_decide` で確認し、
`directSeeds_complete` に渡して生成結果への所属を得る。

## 妥当なSeedを証拠付き待ち導出として公開することを読む

次に `DirectWaitGeneration.lean` の `directWaitDerivations` と `mem_directWaitDerivations` を読む。

読む前に知る語彙:

- 部分型 `{ x : α // 条件 }`
- `List.attach`
- `List.map`
- `List.mem_map`
- `Subtype.ext`

`WaitDerivation n` は新しい実行データを加えた構造体ではなく、Seedと、そのSeedが `Seed.valid` を満たす証拠の組である。
直前の `directSeeds` はSeedの列なので、利用側へ待ち導出として公開するには各要素へ妥当性証拠を付ける必要がある。

`directWaitDerivations` はまず `attach` により、各Seedを「そのSeed本体」と「`directSeeds n` に含まれる証拠」の組へ変える。
次の `map` では `directSeeds_sound` を使い、所属証拠を `Seed.valid` の証拠へ変換する。値の候補を追加したり
削除したりする処理ではなく、直前に確立した健全性を使って同じSeedを証拠付きの型へ持ち上げている。

`mem_directWaitDerivations` は、この持ち上げで妥当な待ち導出を失わないことを示す。任意の
`derivation : WaitDerivation n` はすでに `derivation.2` として妥当性証拠を持つため、
`directSeeds_complete derivation.2` からSeed本体が
`directSeeds n` に含まれると分かる。この所属証拠をSeed本体と組にすれば、`attach` 後の列の要素を構成できる。

最後の `Subtype.ext` は、二つの待ち導出が持つ妥当性証拠そのものを比較せず、Seed本体が同じなら待ち導出も同じだと
結論する。数学的な対象はSeedであり、それが妥当であることの証明手順の違いは別の待ち導出を生まない。

ソース中の例は、直前と同じ赤牌対子のSeedに `native_decide` で妥当性証拠を付けて `WaitDerivation 0` を作り、
`mem_directWaitDerivations` だけで実行用列挙への所属が得られることを示す。

## 生成した牌姿へ待ち牌を戻せることを読む

次に `DirectWaitGeneration.lean` の `hand` と `wait_cons_hand_perm_winningShape` を読む。

読む前に知る語彙:

- `List.erase`
- `List.Perm`
- `List.mergeSort_perm`
- `List.perm_cons_erase`
- `.trans`
- `.symm`

`hand derivation` は、待ち導出が持つ完成形から待ち牌を `erase` で1枚だけ除き、残った牌を牌種順に整列する。
結果は `1 + 3n` 枚のテンパイ牌姿になる。整列するのは、同じ牌を持つ牌姿を入力順に依存しない標準表現で
比較するためである。

`wait_cons_hand_perm_winningShape` は、除いた待ち牌を `hand derivation` の先頭へ戻すと、待ち導出が持つ元の
完成形と順列関係になることを保証する。等号ではなく `List.Perm` なのは、`hand` の整列により牌の並び順が
変わる一方で、各牌種の枚数は保存されるからである。

証明で最初に必要なのは、除こうとした待ち牌が完成形に本当に含まれることである。待ち導出の妥当性条件から、
待ち牌が選択部品に含まれることを `wait_mem_component_of_componentKind_isSome` で取り出す。
`mem_shape_tiles_of_mem_component` は、選択部品への所属を完成形全体への所属へ持ち上げる。

待ち牌の所属が分かれば、`List.perm_cons_erase` により「待ち牌を1枚除き、同じ牌を先頭へ戻した列」は
元の完成形の順列になる。一方、`List.mergeSort_perm` は `hand` の整列前後が順列であることを保証する。
整列後の列の先頭へ待ち牌を加えた順列と、除去して戻した列の順列を `.trans` でつなぐことで結論を得る。

これは全牌姿を探索して結果を確認したものではなく、任意の待ち導出について成り立つ牌の保存則である。
後続の `derivation_waitFor` はこの順列を使い、元の完成形の分割証拠を生成された牌姿へ移す。

ソース中の例では、赤牌対子だけから作った `WaitDerivation 0` について同じ保存則を有限計算で確認する。
`hand` は赤牌1枚となり、待ち牌の赤牌を戻した2枚が元の対子と同じ牌を同数持つ。

## 直接生成した待ち導出を既存Finderへ接続することを読む

次に `DirectWaitGeneration.lean` の `completion` と `completion_mem_findWaitCompletions` を読む。

読む前に知る語彙:

- `IsWaitFor`
- `WinningPartitionSpec`
- `WaitCompletion`
- `mem_findWaitCompletions_iff`
- `.mpr`
- `WinningPartitionSpec.of_perm`

`completion derivation` は、待ち導出が持つ待ち牌と完成形の部品列を、既存Finderが返す `WaitCompletion` の形へ
写す。部品列は `WinningComponent.canonicalize` で正規化するため、面子の並び順だけが異なる同じ分割は同じ結果になる。

`completion_mem_findWaitCompletions` は、面子数 `n` が通常手の上限4以下なら、このcompletionが
`findWaitCompletions (hand derivation)` に必ず含まれると述べる。直接生成器とFinderは実装の探索方向が異なる。
前者は完成形から待ち牌を除き、後者は牌姿へ候補牌を加えて和了分割を探索する。この定理は、直接生成した
一件がFinderの結果としても確認できることを保証する。

Finder所属の仕様 `mem_findWaitCompletions_iff` が要求する証拠は二つある。一つは、候補牌が `hand derivation` の
実際の待ちであることを示す `IsWaitFor` である。内部補題 `derivation_waitFor` は、完成形の牌数、待ち導出の
4枚制限、待ち牌を戻した完成形の分割からこの証拠を作る。仮定 `n ≤ standardHandMentsuCount` は、生成牌姿が
通常手として許される1、4、7、10、13枚の範囲にあることを保証するために使う。

もう一つは、待ち牌を加えた牌姿の `WinningPartitionSpec` である。`winningShape_partition` は元の完成形に対する
分割を構成する。直前に読んだ `wait_cons_hand_perm_winningShape` により、その完成形と
`derivation.1.wait :: hand derivation` は順列関係にあるため、`WinningPartitionSpec.of_perm` で同じ分割仕様を移せる。

最後に `mem_findWaitCompletions_iff` の `.mpr` を使い、この二つの宣言的証拠から実行結果への所属を得る。
これは直接生成器が不正なcompletionを作らないという、既存Finderを基準にした健全性である。逆向き、つまり
Finderの各結果に対応する待ち導出が存在することは、後続の `exists_derivation_of_mem_findWaitCompletions` が扱う。

ソース中の短い例は `n = 0` の任意の待ち導出へ公開定理を適用する。この場合 `0 ≤ 4` は `omega` で解けるため、
待ち導出の具体的な牌を調べずにFinder所属を得られる。

## Finderと直接生成した待ち導出が完全に対応することを読む

次に `DirectWaitGeneration.lean` の `exists_derivation_of_mem_findWaitCompletions` と
`mem_findWaitCompletions_iff_exists_derivation` を読む。

読む前に知る語彙:

- 存在量化 `∃`
- 健全性と完全性
- `constructor`
- `rintro`
- `.mp` と `.mpr`
- `List.Perm`
- `List.mergeSort_perm`

直前の `completion_mem_findWaitCompletions` は、直接生成した待ち導出から既存Finderへ進む一方向を保証した。
逆方向の `exists_derivation_of_mem_findWaitCompletions` は、Finderが返した任意のcompletionから、同じ牌姿、待ち牌、
正規化分割を持つ待ち導出を復元する。復元される面子数 `n` は固定の入力ではなく、Finderが見つけた完成分割から
決まるため、結論では `∃ n, ∃ derivation : WaitDerivation n` と存在量化されている。

復元では、Finderの `WinningPartitionSpec` から雀頭と面子列を取り出し、面子列を標準順へ整列して `WinningShape` を作る。
待ち牌が雀頭に含まれる場合は `.pair`、そうでなければ待ち牌を含む最初の面子位置を `.mentsu` として選ぶ。
この選び方により、面子順と同一面子の選択位置に関する `Seed.valid` の正規化条件も満たせる。
Finder側の `IsWaitFor` からは、通常手の面子数上限と4枚制限を復元する。

`mem_findWaitCompletions_iff_exists_derivation` は、この復元と直前の一方向を組み合わせた公開境界である。
左辺は `found` が既存Finderの実行結果に含まれることを述べる。右辺は、通常手範囲の待ち導出が存在し、
その `hand` が入力牌姿の標準表現に等しく、`completion` が `found` に等しいことを述べる。

左から右は `exists_derivation_of_mem_findWaitCompletions` をそのまま使う。これはFinderが返す結果を待ち導出側が
取りこぼさない完全性に当たる。右から左は存在証拠を `rintro` で取り出し、
`completion_mem_findWaitCompletions` により、まず `hand derivation` に対するFinder所属を得る。

ここで `hand derivation` は整列済みだが、元の `tiles` は任意の順番でよい。`List.mergeSort_perm` は
`canonicalTiles tiles` と `tiles` が同じ牌を同数持つことを保証する。Finder所属を一度
`mem_findWaitCompletions_iff` の宣言的仕様へ変換し、その順列に沿って元の入力順へ移し、再び実行結果への
所属へ戻す。この方向は、待ち導出が表す結果をFinderが取りこぼさないというFinder側の完全性であり、
同時に直接生成したcompletionがFinderの仕様に照らして正しいという直接生成側の健全性でもある。

したがって、完成形から待ち牌を除く直接生成と、牌姿へ候補牌を加えるFinderは、入力順を正規化すれば
同じcompletionを過不足なく表す。`MahjongTests/DirectWaitGeneration.lean` の7枚形の例は、任意の `found` について
この同値定理をそのまま適用している。

## 全待ち導出を有限添字と一対一に対応させる

次に `DirectWaitGeneration.lean` の `waitDerivationCount`、`waitDerivationEquiv`、`ofIndex`、`toIndex`、
`ofIndex_bijective`、二つの往復定理を読む。

読む前に知る語彙:

- `noncomputable def`
- 有限添字型 `Fin n`
- `Fintype.card`
- 型の同値 `A ≃ B`
- `Function.Injective`
- `Function.Surjective`
- `Function.Bijective`
- `@[simp]`

`WaitDerivation n` は有限型なので、値の総数を `Fintype.card` で数えられる。`waitDerivationCount n` はこの総数の略記である。
`Fin (waitDerivationCount n)` は、0以上待ち導出総数未満という範囲内の添字だけを持つ有限型になる。

`waitDerivationEquiv n` は、この有限添字型と `WaitDerivation n` の全単射を `A ≃ B` として表す。
ここでいう完全ハッシュとは、各有効添字がちょうど1つの待ち導出に対応し、各待ち導出にも対応する添字が
ちょうど1つある、という意味である。通常のハッシュ表のように衝突処理を行うのではなく、型どうしの
一対一対応そのものを証拠付きで持つ。

`ofIndex` は添字から待ち導出へ進み、`toIndex` は待ち導出から添字へ戻る。`ofIndex_bijective` の単射部分は、
異なる添字が同じ待ち導出へ衝突しないことを保証する。全射部分は、どの待ち導出にも添字があり、列挙から
欠落しないことを保証する。添字型の大きさ自体が待ち導出総数なので、未使用の有効添字もない。

二つの往復定理は、この対応を操作として使える形にする。

- `toIndex_ofIndex`: 添字から待ち導出へ進んで戻ると、元の添字になる。
- `ofIndex_toIndex`: 待ち導出から添字へ進んで戻ると、元の待ち導出になる。

両方に `@[simp]` が付いているため、ソース中の例のように二つの往復を含む目標は `simp` で解ける。

ただし `waitDerivationEquiv`、`ofIndex`、`toIndex` は `noncomputable` である。この完全ハッシュは全待ち導出の個数と
一対一対応が存在することを述べる数学的仕様であり、通常の実行用列挙器ではない。実際の計算では、
完成形と選択部品から候補を構造的に作る `directWaitDerivations` を使う。

直前に出てきた `sparseCode` との違いにも注意する。`sparseCode` は待ち導出を自然数へ衝突なく写すが、
使われない自然数があり、待ち導出総数と一致する密な範囲を与えない。`waitDerivationEquiv` は非計算的である代わりに、
`Fin (waitDerivationCount n)` という過不足のない有限範囲との完全な対応を保証する。
