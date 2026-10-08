import Mahjong.Basic
import Mahjong.Pattern
import Mahjong.WaitCompletionFinder

/-!
# 発見済みWaitCompletionの待ち分解コード

1つの待ち牌に対して、待ち牌を除いた和了分割の部品がどのような種別へ分かれるかを表す。

`WaitCompletionFinder.findWaitCompletions` が発見した `WaitCompletion` を入力とし、牌の位置を忘れて、
待ち牌を除いた各分割を部品種別の多重集合として扱う。
異なる部品種別に異なる素数を割り当て、その積を代表元とする。
-/
namespace WaitDecompositionCode

open WaitCompletionFinder

/-- 待ち牌を除いた後に見える部品種別。 -/
inductive WaitComponentKind
| tanki
| toitsu
| ryanmen
| kanchan
| penchan
| shuntsu
| koutsu
deriving BEq, DecidableEq, Repr

namespace WaitComponentKind

/-- すべての部品種別。キーの基数を部品数から導くためにも使う。 -/
def all : List WaitComponentKind :=
  [.tanki, .toitsu, .ryanmen, .kanchan, .penchan, .shuntsu, .koutsu]

/-- 部品種別の数。 -/
def count : Nat := all.length

/-- 部品種別に割り当てる素数。積をとることで多重集合の代表コードにする。 -/
def prime : WaitComponentKind → Nat
  | .tanki => 2
  | .toitsu => 3
  | .ryanmen => 5
  | .kanchan => 7
  | .penchan => 11
  | .shuntsu => 13
  | .koutsu => 17

end WaitComponentKind

/-- 具体的な牌種列を保持した部品。 -/
structure WaitComponent where
  kind : WaitComponentKind
  tiles : List Tile
deriving BEq, DecidableEq, Repr

/-- 1つの待ち牌に対する、具体牌付きの待ち分解。 -/
structure WaitDecomposition where
  wait : Tile
  components : List WaitComponent
deriving BEq, DecidableEq, Repr

/-- 2部品の具体牌の位置関係。数牌の距離は同一スート内でだけ定義する。 -/
inductive ComponentTileRelation
| sameNumberedSuit (distance : Nat)
| differentNumberedSuits
| numberedAndHonor
| sameHonor
| differentHonors
| invalidComponents
deriving BEq, DecidableEq, Repr

/--
2つの待ち分解部品の種別と具体牌の位置関係。

部品の順序に依存しないよう、`firstKind` と `secondKind` は
`WaitComponentKind.all` における順序で正規化する。
-/
structure ComponentRelation where
  firstKind : WaitComponentKind
  secondKind : WaitComponentKind
  tileRelation : ComponentTileRelation
deriving BEq, DecidableEq, Repr

/--
従来の素数積コードと、その積を構成した全部品間の位置関係をそのまま保持する実験的シグネチャ。

`relations` は部品対の順序に依存しないよう正規化されている。位置関係をどのように
`waitDecompositionCodes` へ組み込むかは決めず、分類実験で構造を直接比較できる形に留める。
-/
structure WaitDecompositionRelationSignature where
  code : Nat
  relations : List ComponentRelation
deriving BEq, DecidableEq, Repr

/-- 従来コード列と位置関係シグネチャ列を並置した実験的分類。 -/
structure WaitDecompositionRelationClassification where
  codes : List Nat
  signatures : List WaitDecompositionRelationSignature
deriving BEq, DecidableEq, Repr

/-- 完成面子を除いた核成分列と、除去した面子を分けて保持する抽出結果。 -/
structure WaitCoreExtraction where
  wait : Tile
  core : List WaitComponent
  removedMentsu : List WaitComponent
deriving BEq, DecidableEq, Repr

/-- 完成面子を除去済みの `WaitDecomposition`。待ち核であることは生成経路が保証する。 -/
abbrev WaitCore := WaitDecomposition

/-- 牌の位置を忘れ、部品種別だけを残した待ち分解。 -/
structure WaitKindDecomposition where
  wait : Tile
  components : List WaitComponentKind
deriving BEq, DecidableEq, Repr

/-- 待ち牌ごとの抽象形コード。 -/
structure WaitDecompositionCodeEntry where
  wait : Tile
  code : Nat
deriving BEq, DecidableEq, Repr

/-- 完成面子を取り除いて同じ待ち核集合へ還元できるか。 -/
inductive WaitReducibility
| reducible
| irreducible
deriving BEq, DecidableEq, Repr, Fintype

private def completeComponent (component : WinningComponent) : WaitComponent :=
  { kind := match component with
      | .inl _ => .toitsu
      | .inr (.shuntsu _) => .shuntsu
      | .inr (.koutsu _) => .koutsu
    tiles := component.tiles }

/--
通常形の和了分割に現れる和了構成部品から、指定した待ち牌を1枚除いたときに見える不完全部品の種別を返す。

同種2枚の対子から1枚除けば単騎、同種3枚の刻子から1枚除けば対子になる。
順子では、除く位置と端の順子かどうかから両面・嵌張・辺張を区別する。
指定牌がその和了構成部品を構成しない場合は `none` を返す。
-/
def componentKindAfterRemovingWait (wait : Tile) (component : WinningComponent) :
    Option WaitComponentKind :=
  match component with
    | .inl (.toitsu tile) =>
      if tile == wait then some .tanki else none
    | .inr (.koutsu tile) =>
      if tile == wait then some .toitsu else none
    | .inr (.shuntsu (.shuntsu suit start)) =>
      match wait with
      | .honor _ => none
      | .numbered waitSuit rank =>
          if waitSuit != suit then none
          else if rank == ShuntsuStart.firstRank start then
            some (if ShuntsuStart.isLast start then .penchan else .ryanmen)
          else if rank == ShuntsuStart.middleRank start then
            some .kanchan
          else if rank == ShuntsuStart.lastRank start then
            some (if ShuntsuStart.isFirst start then .penchan else .ryanmen)
          else none

      example : componentKindAfterRemovingWait
        (.numbered .Manzu 4) (WinningComponent.pair (.numbered .Manzu 4)) = some .tanki := rfl

      example : componentKindAfterRemovingWait
        (.numbered .Pinzu 6) (WinningComponent.koutsu (.numbered .Pinzu 6)) = some .toitsu := rfl

      example : componentKindAfterRemovingWait
        (.numbered .Souzu 1) (WinningComponent.shuntsu .Souzu ⟨1, by decide⟩) = some .ryanmen := rfl

      example : componentKindAfterRemovingWait
        (.numbered .Souzu 2) (WinningComponent.shuntsu .Souzu ⟨1, by decide⟩) = some .kanchan := rfl

      example : componentKindAfterRemovingWait
        (.numbered .Souzu 2) (WinningComponent.shuntsu .Souzu ⟨0, by decide⟩) = some .penchan := rfl

/--
和了構成部品から指定した待ち牌を1枚除き、種別と残った牌種列を持つ具体的な不完全部品を作る。

`componentKindAfterRemovingWait` が `some kind` を返した場合だけ、和了構成部品の牌種列から
待ち牌を最初の1枚だけ除き、`WaitComponent` にまとめる。
指定牌を除けず種別が `none` の場合は、この関数も `none` を返す。
-/
private def componentAfterRemovingWait (wait : Tile) (component : WinningComponent) :
    Option WaitComponent :=
  (componentKindAfterRemovingWait wait component).map fun kind =>
    { kind, tiles := component.tiles.erase wait }

example : componentAfterRemovingWait
    (.numbered .Manzu 4) (WinningComponent.pair (.numbered .Manzu 4)) =
      some { kind := .tanki, tiles := [.numbered .Manzu 4] } := rfl

private def componentProduct (components : List WaitComponentKind) : Nat :=
  components.foldl (fun product component => product * component.prime) 1

private def keyDigitOffset : Nat := 1
private def tileKeyBase : Nat := Tile.count + keyDigitOffset
private def maxComponentTiles : Nat := mentsuTileCount
private def maxWaitComponents : Nat := standardHandMentsuCount + standardHandPairCount
private def componentTileKeyStride : Nat := tileKeyBase ^ maxComponentTiles
private def decompositionComponentKeyStride : Nat := WaitComponentKind.count * componentTileKeyStride
private def decompositionWaitKeyStride : Nat := decompositionComponentKeyStride ^ maxWaitComponents
private def abstractComponentKeyBase : Nat := WaitComponentKind.count + keyDigitOffset
private def waitKeyStride : Nat := Tile.count

private def waitComponentKey (component : WaitComponentKind) : Nat :=
  WaitComponentKind.all.idxOf component

private def concreteComponentKey (component : WaitComponent) : Nat :=
  waitComponentKey component.kind * componentTileKeyStride +
    component.tiles.foldl
      (fun key tile => key * tileKeyBase + tile.orderKey + keyDigitOffset) 0

private def canonicalizeWaitDecomposition
  (components : List WaitComponent) : List WaitComponent :=
  components.mergeSort fun first second =>
    concreteComponentKey first ≤ concreteComponentKey second

private inductive ComponentTileClass
| numbered (suit : Suit) (ranks : List Nat)
| honor (honor : Honor)
| invalid

private def numberedRanksInSuit (expected : Suit) : List Tile → Option (List Nat)
  | [] => some []
  | .numbered suit rank :: rest =>
      if suit == expected then
        (numberedRanksInSuit expected rest).map (rank.val :: ·)
      else
        none
  | .honor _ :: _ => none

private def allSameHonor (expected : Honor) : List Tile → Bool
  | [] => true
  | .honor honor :: rest => honor == expected && allSameHonor expected rest
  | .numbered _ _ :: _ => false

private def componentTileClass : List Tile → ComponentTileClass
  | [] => .invalid
  | tiles@(.numbered suit _ :: _) =>
      match numberedRanksInSuit suit tiles with
      | some ranks => .numbered suit ranks
      | none => .invalid
  | tiles@(.honor honor :: _) =>
      if allSameHonor honor tiles then .honor honor else .invalid

private def rankDistance (first second : Nat) : Nat :=
  if first ≤ second then second - first else first - second

private def minimumDistanceFrom (first : Nat) : List Nat → Option Nat
  | [] => none
  | second :: rest =>
      let distance := rankDistance first second
      match minimumDistanceFrom first rest with
      | none => some distance
      | some remaining => some (Nat.min distance remaining)

private def minimumRankDistance : List Nat → List Nat → Option Nat
  | [], _ => none
  | first :: rest, second =>
      match minimumDistanceFrom first second, minimumRankDistance rest second with
      | none, none => none
      | some distance, none
      | none, some distance => some distance
      | some distance, some remaining => some (Nat.min distance remaining)

private def componentTileRelation
    (first second : WaitComponent) : ComponentTileRelation :=
  match componentTileClass first.tiles, componentTileClass second.tiles with
  | .numbered firstSuit firstRanks, .numbered secondSuit secondRanks =>
      if firstSuit == secondSuit then
        match minimumRankDistance firstRanks secondRanks with
        | some distance => .sameNumberedSuit distance
        | none => .invalidComponents
      else
        .differentNumberedSuits
  | .numbered _ _, .honor _
  | .honor _, .numbered _ _ => .numberedAndHonor
  | .honor firstHonor, .honor secondHonor =>
      if firstHonor == secondHonor then .sameHonor else .differentHonors
  | _, _ => .invalidComponents

private def componentRelationKey (relation : ComponentRelation) : Nat :=
  let tileRelationKey := match relation.tileRelation with
    | .sameNumberedSuit distance => distance
    | .differentNumberedSuits => numberedRankCount
    | .numberedAndHonor => numberedRankCount + 1
    | .sameHonor => numberedRankCount + 2
    | .differentHonors => numberedRankCount + 3
    | .invalidComponents => numberedRankCount + 4
  (waitComponentKey relation.firstKind * WaitComponentKind.count +
      waitComponentKey relation.secondKind) *
    (numberedRankCount + 5) + tileRelationKey

/-- 2つの具体牌付き部品から、部品順に依存しない位置関係を作る。 -/
def componentRelation (first second : WaitComponent) : ComponentRelation :=
  if waitComponentKey first.kind ≤ waitComponentKey second.kind then
    { firstKind := first.kind
      secondKind := second.kind
      tileRelation := componentTileRelation first second }
  else
    { firstKind := second.kind
      secondKind := first.kind
      tileRelation := componentTileRelation first second }

/-- 具体牌付き部品列から、異なる2部品の全組合せに対する位置関係を正規化して列挙する。 -/
def componentRelations : List WaitComponent → List ComponentRelation
  | [] => []
  | first :: rest =>
      (rest.map (componentRelation first) ++ componentRelations rest)
        |>.mergeSort fun left right => componentRelationKey left ≤ componentRelationKey right

private def componentRelationsKey (relations : List ComponentRelation) : Nat :=
  let base := WaitComponentKind.count * WaitComponentKind.count * (numberedRankCount + 5) + 1
  relations.foldl (fun key relation => key * base + componentRelationKey relation + 1) 0

private def relationSignatureLE
    (first second : WaitDecompositionRelationSignature) : Bool :=
  if first.code == second.code then
    componentRelationsKey first.relations ≤ componentRelationsKey second.relations
  else
    first.code < second.code

def waitDecompositionKey (decomposition : WaitDecomposition) : Nat :=
  decomposition.wait.orderKey * decompositionWaitKeyStride +
    decomposition.components.foldl
      (fun key component => key * decompositionComponentKeyStride + concreteComponentKey component) 0

private def waitKindDecompositionKey (decomposition : WaitKindDecomposition) : Nat :=
  decomposition.components.foldl
    (fun key component =>
      key * abstractComponentKeyBase + waitComponentKey component + keyDigitOffset) 0 *
      waitKeyStride +
    decomposition.wait.orderKey

private def waitDecompositionCodeEntryKey (entry : WaitDecompositionCodeEntry) : Nat :=
  entry.code * waitKeyStride + entry.wait.orderKey

private def deduplicateAndSortBy {α : Type} [BEq α]
    (key : α → Nat) (values : List α) : List α :=
  values.eraseDups.mergeSort fun first second => key first ≤ key second

/--
1つの待ち牌と和了分割から、待ち牌を除く和了構成部品の選び方をすべて列挙する。

各結果では、分割中の和了構成部品をちょうど1つ選んで `componentAfterRemovingWait` で不完全部品へ変え、
それ以外は `completeComponent` で完成した種別のまま残す。指定牌を除けない部品は選択肢にせず、
同じ待ち牌を除ける部品が複数あれば、除去元ごとに別の待ち分解を作る。
-/
private def componentDecompositions (completion : WaitCompletion) :
    List (List WaitComponent) :=
  let rec selectWinningComponent : List WinningComponent → List (List WaitComponent)
    | [] => []
    | component :: rest =>
        let later := (selectWinningComponent rest).map fun extraction =>
          completeComponent component :: extraction
        match componentAfterRemovingWait completion.wait component with
        | some incomplete =>
            (incomplete :: rest.map completeComponent) :: later
        | none => later
  selectWinningComponent completion.winningComponents.toList

example : componentDecompositions
    { wait := .numbered .Manzu 4
      winningComponents :=
        CanonicalWinningComponents.ofList
          [WinningComponent.pair (.numbered .Manzu 4), WinningComponent.shuntsu .Pinzu ⟨0, by decide⟩] } =
    [[{ kind := .tanki, tiles := [.numbered .Manzu 4] },
      { kind := .shuntsu, tiles :=
        [.numbered .Pinzu 0, .numbered .Pinzu 1, .numbered .Pinzu 2] }]] := by
  native_decide

/--
発見済みの待ちと和了分割をすべて処理し、待ち牌ごとの具体牌付き待ち分解を正規化して列挙する。

各 `WaitCompletion` に `componentDecompositions` を適用し、待ち牌と部品列を `WaitDecomposition` にまとめる。
部品列を一定の順序に並べた後、全completionから得た同一待ち分解の重複を除いて結果全体も整列する。
そのため、和了分割内の部品順や同じcompletionの重複は、返り値を変えない。
-/
def waitDecompositions
    (completions : List WaitCompletion) : List WaitDecomposition :=
  let entries := completions.flatMap fun completion =>
      (componentDecompositions completion).map fun decomposition =>
        { wait := completion.wait
          components := canonicalizeWaitDecomposition decomposition }
  deduplicateAndSortBy waitDecompositionKey entries

example : waitDecompositions
    [{ wait := .numbered .Manzu 4
       winningComponents :=
         CanonicalWinningComponents.ofList
           [WinningComponent.shuntsu .Pinzu ⟨0, by decide⟩, WinningComponent.pair (.numbered .Manzu 4)] },
     { wait := .numbered .Manzu 4
       winningComponents :=
         CanonicalWinningComponents.ofList
           [WinningComponent.pair (.numbered .Manzu 4), WinningComponent.shuntsu .Pinzu ⟨0, by decide⟩] }] =
    [{ wait := .numbered .Manzu 4
       components :=
         [{ kind := .tanki, tiles := [.numbered .Manzu 4] },
          { kind := .shuntsu, tiles :=
            [.numbered .Pinzu 0, .numbered .Pinzu 1, .numbered .Pinzu 2] }] }] := by
  native_decide

private def isCompletedMentsu (component : WaitComponent) : Bool :=
  component.kind == .shuntsu || component.kind == .koutsu

/--
1つの具体牌付き待ち分解を、待ち核の成分列と、そこから分離した完成面子に分ける。

順子 `.shuntsu` と刻子 `.koutsu` は `removedMentsu` に移し、それ以外の不完全部品は `core` に残す。
待ち牌 `wait` と各部品の具体的な牌種列は保持するため、後続処理は「どの完成面子を除いたか」を失わずに、
完成面子を除いた核成分列だけを比較できる。
この関数は1つの待ち分解を二分するだけであり、牌姿全体が可約か既約かは判定しない。

読むためのLean語彙: `structure`, `filter`, `fun`, `!`。
-/
def extractWaitCore (decomposition : WaitDecomposition) : WaitCoreExtraction :=
  { wait := decomposition.wait
    core := decomposition.components.filter fun component => !isCompletedMentsu component
    removedMentsu := decomposition.components.filter isCompletedMentsu }

/-- 発見済みの待ち分解から、完成面子を除いた待ち核を抽出する。 -/
def waitCoreExtractions
    (completions : List WaitCompletion) : List WaitCoreExtraction :=
  (waitDecompositions completions).map extractWaitCore

/--
発見済みの全待ち分解から、比較可能な待ち核集合を作る。

各 `WaitCoreExtraction` から `removedMentsu` を忘れ、待ち牌 `wait` と核成分列 `core` だけを
`WaitCore` に残す。同じ待ち核が複数の和了分割から得られても1件として扱えるよう重複を除き、
待ち牌と核成分列から作るキーの順に整列する。

返り値は `List WaitCore` だが、重複がなく順序も正規化されているため、待ち核の有限集合として比較できる。
読むためのLean語彙: `map`, `fun`, `|>`。
-/
def waitCores (completions : List WaitCompletion) : List WaitCore :=
  waitCoreExtractions completions
    |>.map (fun extraction => { wait := extraction.wait, components := extraction.core })
    |> deduplicateAndSortBy waitDecompositionKey

/-- Exact compact key for one concrete wait core. -/
def waitCoreKey (core : WaitCore) : Nat :=
  waitDecompositionKey core

/-- Exact compact keys for a normalized wait-core list. -/
def waitCoreKeys (cores : List WaitCore) : List Nat :=
  cores.map waitCoreKey

/--
発見済みの具体牌付き待ち分解から各部品の牌種列を忘れ、部品種別だけの待ち分解へ変換する。

待ち牌 `wait` は保持し、各 `WaitComponent` は `kind` だけに写す。
具体牌が異なっても待ち牌と部品種別列が同じ待ち分解は重複を除き、一定の順序に整列する。
この段階では部品種別列をまだ数値コードには変換しない。
-/
def waitKindDecompositions
    (completions : List WaitCompletion) : List WaitKindDecomposition :=
  waitDecompositions completions
    |>.map (fun decomposition =>
      { wait := decomposition.wait
        components := decomposition.components.map (fun component => component.kind) })
    |> deduplicateAndSortBy waitKindDecompositionKey

example : waitKindDecompositions
    [{ wait := .numbered .Manzu 4
       winningComponents :=
         CanonicalWinningComponents.ofList
           [WinningComponent.pair (.numbered .Manzu 4), WinningComponent.shuntsu .Pinzu ⟨0, by decide⟩] },
     { wait := .numbered .Manzu 4
       winningComponents :=
         CanonicalWinningComponents.ofList
           [WinningComponent.pair (.numbered .Manzu 4), WinningComponent.shuntsu .Pinzu ⟨3, by decide⟩] }] =
    [{ wait := .numbered .Manzu 4, components := [.tanki, .shuntsu] }] := by
  native_decide

/--
種別だけの待ち分解を素数積へ変換し、待ち牌ごとのコードとして列挙する。

各部品種別に割り当てた素数をすべて掛けるため、コードは部品順を忘れる一方、
各種別が現れる個数を素因数の指数として保持する。待ち牌はコードと別のフィールドに残し、
同じ待ち牌とコードの重複を除いて一定の順序に整列する。
-/
def waitDecompositionCodeEntries
    (completions : List WaitCompletion) : List WaitDecompositionCodeEntry :=
  waitKindDecompositions completions
    |>.map (fun decomposition =>
      { wait := decomposition.wait
        code := componentProduct decomposition.components })
    |> deduplicateAndSortBy waitDecompositionCodeEntryKey

example : waitDecompositionCodeEntries
    [{ wait := .numbered .Manzu 4
       winningComponents :=
         CanonicalWinningComponents.ofList
           [WinningComponent.pair (.numbered .Manzu 4), WinningComponent.shuntsu .Pinzu ⟨0, by decide⟩] }] =
    [{ wait := .numbered .Manzu 4, code := 26 }] := by
  native_decide

/--
待ち牌を忘れ、発見済みの待ち分解に現れる部品種別コードだけを列挙する。

待ち牌を忘れた後も、コードの出現回数を保ったままコード値の順に整列する。
この結果の一致は部品種別の多重集合とその出現回数が同じことを表すが、
待ち牌、具体牌、元の牌姿の一致は表さない。
-/
def waitDecompositionCodes (completions : List WaitCompletion) : List Nat :=
  waitDecompositionCodeEntries completions
    |>.map (fun entry => entry.code)
    |>.mergeSort fun first second => first ≤ second

private structure WaitDecompositionRelationEntry where
  wait : Tile
  signature : WaitDecompositionRelationSignature
deriving BEq, DecidableEq

/--
発見済みの待ち分解ごとに、従来コードと全部品対の具体的位置関係を対応付ける。

同じ待ち牌についてコードと関係がともに同じ分解は重複除去する。一方、待ち牌が異なる場合は、
`waitDecompositionCodes` と同様に待ち牌を忘れた後も出現回数を保持する。
-/
def waitDecompositionRelationSignatures
    (completions : List WaitCompletion) : List WaitDecompositionRelationSignature :=
  waitDecompositions completions
    |>.map (fun decomposition =>
      { wait := decomposition.wait
        signature :=
          { code := componentProduct (decomposition.components.map (·.kind))
            relations := componentRelations decomposition.components } : WaitDecompositionRelationEntry })
    |>.eraseDups
    |>.map (·.signature)
    |>.mergeSort relationSignatureLE

/--
従来のコード分類を維持したまま、具体的な部品間関係を付加した実験的分類を返す。

`codes` と `signatures` は独立に正規化する。後者にも対応する従来コードを含めるため、
同じコードが位置関係によって複数のシグネチャへ分かれた場合を観察できる。
-/
def waitDecompositionRelationClassification
    (completions : List WaitCompletion) : WaitDecompositionRelationClassification :=
  { codes := waitDecompositionCodes completions
    signatures := waitDecompositionRelationSignatures completions }

example : waitDecompositionCodes
    [{ wait := .numbered .Manzu 4
       winningComponents :=
         CanonicalWinningComponents.ofList
           [WinningComponent.pair (.numbered .Manzu 4), WinningComponent.shuntsu .Pinzu ⟨0, by decide⟩] },
     { wait := .numbered .Manzu 5
       winningComponents :=
         CanonicalWinningComponents.ofList
           [WinningComponent.pair (.numbered .Manzu 5), WinningComponent.shuntsu .Pinzu ⟨0, by decide⟩] }] =
    [26, 26] := by
  native_decide

/-!
### 待ち分解コード列を1つの自然数へ埋め込む

`waitDecompositionCodes` は昇順の `List Nat` であり、牌姿データベースのキーには使いにくい。
そこで各桁を `[0, base)` に収めた「双方向基数」記法で1つの `Nat` へ埋め込み、逆関数で元の列を復元できるようにする。
桁の値へ `1` を足してから位取りに使うため、埋め込んだ値が `0` であることが列の終わりの合図になり、
長さを別に覚える必要がない。
-/

/-- 桁の値をすべて `[0, base)` に収めた `List Nat` を、`base` 進の双方向記数法で1つの自然数へ埋め込む。 -/
private def bijectiveBaseEncode (base : Nat) : List Nat → Nat
  | [] => 0
  | digit :: rest => (digit + 1) + base * bijectiveBaseEncode base rest

/-- `bijectiveBaseEncode` の逆関数。`code = 0` を列の終わりの合図として使う。 -/
private def bijectiveBaseDecode (base : Nat) (code : Nat) : List Nat :=
  if h : code = 0 then
    []
  else
    have hle : (code - 1) / base ≤ code - 1 := Nat.div_le_self ..
    (code - 1) % base :: bijectiveBaseDecode base ((code - 1) / base)
termination_by code
decreasing_by omega

/-- 桁の値がすべて `base` 未満なら、`bijectiveBaseDecode` は `bijectiveBaseEncode` の逆になる。 -/
theorem bijectiveBaseDecode_encode (base : Nat) (digits : List Nat)
    (bounded : ∀ digit ∈ digits, digit < base) :
    bijectiveBaseDecode base (bijectiveBaseEncode base digits) = digits := by
  induction digits with
  | nil => simp [bijectiveBaseEncode, bijectiveBaseDecode]
  | cons digit rest ih =>
      have digitBound : digit < base := bounded digit (List.mem_cons_self ..)
      have restBound : ∀ d ∈ rest, d < base := fun d hd => bounded d (List.mem_cons_of_mem _ hd)
      have hne : (digit + 1) + base * bijectiveBaseEncode base rest ≠ 0 := by omega
      have hprev : (digit + 1) + base * bijectiveBaseEncode base rest - 1
          = digit + base * bijectiveBaseEncode base rest := by omega
      rw [bijectiveBaseEncode, bijectiveBaseDecode]
      simp only [hne, dite_false, hprev]
      rw [Nat.add_mul_mod_self_left, Nat.mod_eq_of_lt digitBound,
        Nat.add_mul_div_left _ _ (Nat.pos_of_ne_zero (by omega)),
        Nat.div_eq_of_lt digitBound, Nat.zero_add, ih restBound]

/-!
### 素数積は本質ではない: 実現可能なコードを直接数え上げて詰め直す

`componentProduct` が素数の積を選んだのは、種別の多重集合を一意な自然数へ変える手段の1つに過ぎない。
実際に道具として必要なのは「重複なく一意な値」であって、値が素数の積である必要はない。
そこで、部品種別が `WaitComponentKind.count` 通りしかなく、1つの待ち分解の部品数が高々
`maxWaitComponents` であることを使い、実現可能な積の値をすべて数え上げてから、その中での順位
（0始まりの通し番号）に詰め直す。値の集合は高々 792 通りしかないため、素数の積そのもの
（最大 `17 ^ maxWaitComponents = 1419857`）よりずっと狭い範囲に収まる。
-/

/-- 与えられた並び順（`alphabet`）から、順序を保ったまま重複を許して `length` 個選ぶ選び方をすべて列挙する。 -/
def combinationsWithRepetitionOver {α : Type} : List α → Nat → List (List α)
  | _, 0 => [[]]
  | [], _ + 1 => []
  | a :: rest, n + 1 =>
      (combinationsWithRepetitionOver (a :: rest) n).map (a :: ·) ++
        combinationsWithRepetitionOver rest (n + 1)

/-- `componentProduct` が実際に取り得る値をすべて数え上げ、重複を除いて昇順に並べたもの。 -/
private def waitDecompositionCodeSpace : List Nat :=
  ((List.range (maxWaitComponents + 1)).flatMap fun length =>
      combinationsWithRepetitionOver WaitComponentKind.all length)
    |>.map componentProduct
    |>.eraseDups
    |>.mergeSort fun first second => first ≤ second

example : waitDecompositionCodeSpace.length = 792 := by native_decide

/-- `waitDecompositionCodeSpace` の中での `code` の順位。素数の積を、その値の代わりに通し番号へ詰め直す。 -/
private def compactCodeRank (code : Nat) : Nat :=
  waitDecompositionCodeSpace.idxOf code

/-- `compactCodeRank` の逆関数。通し番号から元の素数積コードを復元する。 -/
private def compactCodeOfRank (rank : Nat) : Nat :=
  waitDecompositionCodeSpace.getD rank 0

/-- `code` が `componentProduct` の実現可能値なら、通し番号への詰め直しから元のコードをちょうど復元できる。 -/
private theorem compactCodeOfRank_rank {code : Nat} (h : code ∈ waitDecompositionCodeSpace) :
    compactCodeOfRank (compactCodeRank code) = code := by
  have hlt : waitDecompositionCodeSpace.idxOf code < waitDecompositionCodeSpace.length :=
    List.idxOf_lt_length_of_mem h
  have hp : (waitDecompositionCodeSpace[waitDecompositionCodeSpace.idxOf code]'hlt == code) = true :=
    List.findIdx_getElem (w := hlt)
  simp only [compactCodeOfRank, compactCodeRank, List.getD_eq_getElem?_getD,
    List.getElem?_eq_getElem hlt, Option.getD_some]
  exact eq_of_beq hp

/--
`waitDecompositionCodes` が返す多重集合を、牌姿データベースのキーとして使える1つの自然数へ埋め込む。

各部品コードをまず `waitDecompositionCodeSpace` 上の通し番号へ詰め直してから、双方向基数記法で結合する。
桁の基数が `waitDecompositionCodeSpace.length`（792以下）になるため、同じ長さの列でも素数の積を
そのまま桁に使うより狭い範囲に収まる。ただし、キーの値は列の長さに応じて基数のべき乗で大きくなる
ことに変わりはなく、長い列では典型的な64bit整数の範囲を超えうる。DBの列は多倍長整数型か文字列/BLOB
での保存を検討する。
-/
def waitDecompositionCodesKey (codes : List Nat) : Nat :=
  bijectiveBaseEncode waitDecompositionCodeSpace.length (codes.map compactCodeRank)

/-- `waitDecompositionCodesKey` の逆関数。キーから元の部品コード列を復元する。 -/
def waitDecompositionCodesOfKey (key : Nat) : List Nat :=
  (bijectiveBaseDecode waitDecompositionCodeSpace.length key).map compactCodeOfRank

/-- 各部品コードが `componentProduct` の実現可能値なら、キーから元の列をちょうど復元できる。 -/
theorem waitDecompositionCodesOfKey_key (codes : List Nat)
    (realizable : ∀ code ∈ codes, code ∈ waitDecompositionCodeSpace) :
    waitDecompositionCodesOfKey (waitDecompositionCodesKey codes) = codes := by
  unfold waitDecompositionCodesOfKey waitDecompositionCodesKey
  have hbound : ∀ rank ∈ codes.map compactCodeRank, rank < waitDecompositionCodeSpace.length :=
    fun rank hrank => by
      obtain ⟨code, hcode, hrank⟩ := List.mem_map.mp hrank
      exact hrank ▸ List.idxOf_lt_length_of_mem (realizable code hcode)
  rw [bijectiveBaseDecode_encode _ _ hbound]
  clear hbound
  induction codes with
  | nil => rfl
  | cons code rest ih =>
      have hcode : code ∈ waitDecompositionCodeSpace := realizable code (List.mem_cons_self ..)
      have hrest : ∀ c ∈ rest, c ∈ waitDecompositionCodeSpace :=
        fun c hc => realizable c (List.mem_cons_of_mem _ hc)
      simp [compactCodeOfRank_rank hcode, ih hrest]

example : waitDecompositionCodesOfKey
    (waitDecompositionCodesKey [117, 117, 255, 255, 357, 578]) =
    [117, 117, 255, 255, 357, 578] := by
  native_decide

/-- 牌列から得られる待ち核集合。 -/
def findWaitCores (tiles : List Tile) : List WaitCore :=
  waitCores (WaitCompletionFinder.findWaitCompletions tiles)

/--
完成面子を1つ除いても、同じ待ち核集合を持つ聴牌形が残る削減候補を列挙する。

`findWaitCores tiles` は除去候補に依存しないため、ループの外で1回だけ計算して使い回す。
読むためのLean語彙: `let`, `List.filter`。
-/
def waitCorePreservingMentsuReductions (tiles : List Tile) : List (List Tile) :=
  let originalCores := findWaitCores tiles
  mentsuReductions tiles |>.filter fun remaining =>
    !(waitingTiles remaining).isEmpty && findWaitCores remaining == originalCores

/--
完成面子を1つ除いても、同じ待ち核集合を持つ聴牌形が残るかを判定する。

`waitCorePreservingMentsuReductions tiles` が列挙する成功候補が1つでもあるかを調べる。
待ち牌が残るという条件により、たまたま空の待ち核集合どうしが一致する場合は可約とみなさない。

`1 < tiles.length` は、完成面子を含み得ない1枚単騎を除外するための入口条件である。
読むためのLean語彙: `Bool`, `&&`, `!`, `List.isEmpty`。
-/
def canReduceMentsuPreservingWaitCores (tiles : List Tile) : Bool :=
  1 < tiles.length && !(waitCorePreservingMentsuReductions tiles).isEmpty

/-- 聴牌の証拠を前提に、待ち核集合を保った面子除去による可約性を計算する。 -/
def reducibility (tiles : List Tile) (_ : WaitCompletionFinder.IsTenpai tiles) :
    WaitReducibility :=
  if canReduceMentsuPreservingWaitCores tiles then .reducible else .irreducible

/-- 聴牌なら可約性を返し、非聴牌なら `none` を返す。 -/
def determineReducibility (tiles : List Tile) : Option WaitReducibility :=
  if tenpai : WaitCompletionFinder.IsTenpai tiles then
    some (reducibility tiles tenpai)
  else
    none

theorem reducibility_eq_reducible_iff (tiles : List Tile)
    (tenpai : WaitCompletionFinder.IsTenpai tiles) :
    reducibility tiles tenpai = .reducible ↔
      canReduceMentsuPreservingWaitCores tiles = true := by
  simp [reducibility]

theorem reducibility_eq_irreducible_iff (tiles : List Tile)
    (tenpai : WaitCompletionFinder.IsTenpai tiles) :
    reducibility tiles tenpai = .irreducible ↔
      canReduceMentsuPreservingWaitCores tiles = false := by
  simp [reducibility]

def findWaitDecompositionCodes (tiles : List Tile) : List Nat :=
  waitDecompositionCodes (WaitCompletionFinder.findWaitCompletions tiles)

/-- 牌列から従来コードと部品間関係を併記した実験的分類を計算する。 -/
def findWaitDecompositionRelationClassification
    (tiles : List Tile) : WaitDecompositionRelationClassification :=
  waitDecompositionRelationClassification (WaitCompletionFinder.findWaitCompletions tiles)

/--
数牌1スートの既約な7枚待ち53形。最小ランクが1になるよう正規化している。
`m` を `p` や `s` に置き換えるか、ランク1--9を外れない範囲で平行移動しても、
同値な具体例が得られる。
-/
def irreducibleSingleSuitSevenTileExamples : List (String × List Tile) :=
  [("1345666m", manzu [0, 2, 3, 4, 5, 5, 5]),
   ("1234666m", manzu [0, 1, 2, 3, 5, 5, 5]),
   ("1234567m", manzu [0, 1, 2, 3, 4, 5, 6]),
   ("1234555m", manzu [0, 1, 2, 3, 4, 4, 4]),
   ("1234456m", manzu [0, 1, 2, 3, 3, 4, 5]),
   ("1233334m", manzu [0, 1, 2, 2, 2, 2, 3]),
   ("1223344m", manzu [0, 1, 1, 2, 2, 3, 3]),
   ("1222345m", manzu [0, 1, 1, 1, 2, 3, 4]),
   ("1222333m", manzu [0, 1, 1, 1, 2, 2, 2]),
   ("1222234m", manzu [0, 1, 1, 1, 1, 2, 3]),
   ("1178999m", manzu [0, 0, 6, 7, 8, 8, 8]),
   ("1167888m", manzu [0, 0, 5, 6, 7, 7, 7]),
   ("1166678m", manzu [0, 0, 5, 5, 5, 6, 7]),
   ("1156777m", manzu [0, 0, 4, 5, 6, 6, 6]),
   ("1155567m", manzu [0, 0, 4, 4, 4, 5, 6]),
   ("1145678m", manzu [0, 0, 3, 4, 5, 6, 7]),
   ("1145666m", manzu [0, 0, 3, 4, 5, 5, 5]),
   ("1144456m", manzu [0, 0, 3, 3, 3, 4, 5]),
   ("1134567m", manzu [0, 0, 2, 3, 4, 5, 6]),
   ("1134555m", manzu [0, 0, 2, 3, 4, 4, 4]),
   ("1133345m", manzu [0, 0, 2, 2, 2, 3, 4]),
   ("1123456m", manzu [0, 0, 1, 2, 3, 4, 5]),
   ("1123444m", manzu [0, 0, 1, 2, 3, 3, 3]),
   ("1123344m", manzu [0, 0, 1, 2, 2, 3, 3]),
   ("1123333m", manzu [0, 0, 1, 2, 2, 2, 2]),
   ("1122344m", manzu [0, 0, 1, 1, 2, 3, 3]),
   ("1122334m", manzu [0, 0, 1, 1, 2, 2, 3]),
   ("1122333m", manzu [0, 0, 1, 1, 2, 2, 2]),
   ("1122234m", manzu [0, 0, 1, 1, 1, 2, 3]),
   ("1122233m", manzu [0, 0, 1, 1, 1, 2, 2]),
   ("1122223m", manzu [0, 0, 1, 1, 1, 1, 2]),
   ("1113555m", manzu [0, 0, 0, 2, 4, 4, 4]),
   ("1113456m", manzu [0, 0, 0, 2, 3, 4, 5]),
   ("1113444m", manzu [0, 0, 0, 2, 3, 3, 3]),
   ("1113345m", manzu [0, 0, 0, 2, 2, 3, 4]),
   ("1113333m", manzu [0, 0, 0, 2, 2, 2, 2]),
   ("1112444m", manzu [0, 0, 0, 1, 3, 3, 3]),
   ("1112399m", manzu [0, 0, 0, 1, 2, 8, 8]),
   ("1112388m", manzu [0, 0, 0, 1, 2, 7, 7]),
   ("1112377m", manzu [0, 0, 0, 1, 2, 6, 6]),
   ("1112366m", manzu [0, 0, 0, 1, 2, 5, 5]),
   ("1112355m", manzu [0, 0, 0, 1, 2, 4, 4]),
   ("1112346m", manzu [0, 0, 0, 1, 2, 3, 5]),
   ("1112345m", manzu [0, 0, 0, 1, 2, 3, 4]),
   ("1112344m", manzu [0, 0, 0, 1, 2, 3, 3]),
   ("1112334m", manzu [0, 0, 0, 1, 2, 2, 3]),
   ("1112333m", manzu [0, 0, 0, 1, 2, 2, 2]),
   ("1112234m", manzu [0, 0, 0, 1, 1, 2, 3]),
   ("1112233m", manzu [0, 0, 0, 1, 1, 2, 2]),
   ("1112223m", manzu [0, 0, 0, 1, 1, 1, 2]),
   ("1112222m", manzu [0, 0, 0, 1, 1, 1, 1]),
   ("1111333m", manzu [0, 0, 0, 0, 2, 2, 2]),
   ("1111222m", manzu [0, 0, 0, 0, 1, 1, 1])]

private def insertWaitDecompositionCodeClass (entry : String × List Nat) :
  List (List Nat × List String) → List (List Nat × List String)
  | [] => [(entry.2, [entry.1])]
  | current :: rest =>
      if current.1 == entry.2 then
        (current.1, current.2 ++ [entry.1]) :: rest
      else
        current :: insertWaitDecompositionCodeClass entry rest

def irreducibleSevenTileWaitDecompositionCodeClasses : List (List Nat × List String) :=
  irreducibleSingleSuitSevenTileExamples.foldl (fun classes entry =>
    insertWaitDecompositionCodeClass (entry.1, findWaitDecompositionCodes entry.2) classes) []

end WaitDecompositionCode
