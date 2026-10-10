import Mahjong.DirectWaitGeneration
import Std.Data.HashMap

/-!
# 麻雀計算モジュールの共通処理
-/

namespace MahjongComputations

open WaitDecompositionCode

/-- 牌種ごとの枚数を、物理上限より1大きい基数で符号化した多重集合キー。 -/
def tileMultisetKey (tiles : List Tile) : Nat :=
  Tile.all.foldl (fun key tile => key * (copiesPerTile + 1) + tiles.count tile) 0

/-- 各牌種を0枚から物理上限まで選ぶ合法牌多重集合の共通畳み込み。 -/
private def foldLegalTileMultisetsOfLength {α : Type}
    (empty : α) (combine : α → α → α)
    (onComplete : α) (prependCopies : Tile → Nat → α → α) :
    Nat → List Tile → α
  | length, [] =>
      if length == 0 then onComplete else empty
  | length, tile :: rest =>
      (List.range (Nat.min copiesPerTile length + 1)).foldl
        (fun result copies =>
          combine result (prependCopies tile copies
            (foldLegalTileMultisetsOfLength empty combine onComplete prependCopies
              (length - copies) rest)))
        empty
termination_by _ tiles => tiles.length

/-- 指定した牌種からなる、指定枚数の合法な牌多重集合。 -/
def legalTileMultisetsOfLength (length : Nat) (tiles : List Tile) : List (List Tile) :=
  foldLegalTileMultisetsOfLength [] List.append [[]]
    (fun tile copies tails => tails.map fun tail => List.replicate copies tile ++ tail)
    length tiles

/-- 指定した牌種からなる、指定枚数の合法な牌多重集合の個数。 -/
def countLegalTileMultisetsOfLength (length : Nat) (tiles : List Tile) : Nat :=
  foldLegalTileMultisetsOfLength 0 Nat.add 1 (fun _ _ count => count) length tiles

/-- 牌姿ごとに完成情報を集約する前の1件。 -/
structure WaitCompletionEntry where
  tiles : List Tile
  completion : WaitCompletion
deriving BEq, DecidableEq, Repr

/-- 同じ牌姿から得られた重複のない完成情報群。 -/
structure WaitCompletionGroup where
  tiles : List Tile
  completions : List WaitCompletion
deriving BEq, DecidableEq, Repr

private def waitCompletionEntryKeyLE
    (first second : WaitCompletionEntry) : Bool :=
  decide (tileMultisetKey first.tiles ≤ tileMultisetKey second.tiles)

/-- Insert a completion unless the same normalized completion is already present. -/
def insertCompletion
    (completion : WaitCompletion) (completions : List WaitCompletion) : List WaitCompletion :=
  if completions.contains completion then completions else completion :: completions

private def groupSortedWaitCompletionEntry
    (groups : List WaitCompletionGroup) (entry : WaitCompletionEntry) :
    List WaitCompletionGroup :=
  let key := tileMultisetKey entry.tiles
  match groups with
  | [] => [{ tiles := entry.tiles, completions := [entry.completion] }]
  | group :: rest =>
      if tileMultisetKey group.tiles == key then
        { group with completions := insertCompletion entry.completion group.completions } :: rest
      else
        { tiles := entry.tiles, completions := [entry.completion] } :: groups

/-- 完成情報を牌姿ごとにまとめ、同一牌姿内の重複を除く。 -/
def groupWaitCompletions (entries : List WaitCompletionEntry) : List WaitCompletionGroup :=
  entries.mergeSort waitCompletionEntryKeyLE
    |>.foldl groupSortedWaitCompletionEntry []

/-- 直接導出を、同じ牌姿から得られた完成情報群へまとめる。 -/
def groupWaitDerivations {mentsuCount : Nat}
    (derivations : List (DirectWaitGeneration.WaitDerivation mentsuCount)) :
    List WaitCompletionGroup :=
  derivations
    |>.map (fun derivation =>
      { tiles := DirectWaitGeneration.hand derivation
        completion := DirectWaitGeneration.completion derivation })
    |> groupWaitCompletions

/-!
### 面子の並べ替えだけが違う直接生成の重複を避け、生成結果を一度に保持しない

`DirectWaitGeneration.directWaitDerivations` は `n` 個の面子を `Fin n → MentsuCandidate` という
順序付き関数として生成するため、同じ面子の多重集合でも並べ替えの数（最大 `n !`）だけ重複して
生成し、その大半を `Seed.valid` の正規化条件（`mentsuCanonical`）で捨てている。
さらに、生成した全件を `List` として一度に保持してから牌姿ごとにソート・グループ化する実装は、
面子が増えるほど生成件数（10枚形で数百万件規模）に比例したピークメモリを必要とする。

以下では、`mentsuCanonical` と同じ順序（`WinningComponent.orderKey` の昇順）で最初から
非減少列だけを畳み込みで直接処理し、`Seed.valid` を満たした瞬間に牌姿キーのハッシュマップへ
反映して捨てる。生成した `WaitDerivation` の全件を並べたリストはどこにも保持しないため、
ピークメモリは生成件数ではなく、重複除去後の牌姿の種類数に比例する。
-/

private def canonicalMentsuAlphabet : List MentsuCandidate :=
  MentsuCandidate.candidates.mergeSort fun first second =>
    decide (WinningComponent.orderKey (.inr first) ≤ WinningComponent.orderKey (.inr second))

private def defaultMentsuCandidate : MentsuCandidate := .koutsu (.honor .East)

private def mentsuListToFunction (n : Nat) (mentsuList : List MentsuCandidate) :
    Fin n → MentsuCandidate :=
  fun i => mentsuList.getD i.val defaultMentsuCandidate

open DirectWaitGeneration in
/--
指定した雀頭牌について、面子の割り当てを `mentsuCanonical` と同じ順序で非減少列に限って
直接畳み込み、正規化済みの `WaitDerivation` それぞれを `f` で処理する。
-/
def foldCanonicalDirectWaitDerivationsForPairTiles {n : Nat} {α : Type}
    (pairTiles : List Tile) (init : α) (f : α → WaitDerivation n → α) : α :=
  pairTiles.foldl (init := init) fun acc tile =>
    (WaitDecompositionCode.combinationsWithRepetitionOver canonicalMentsuAlphabet n).foldl
      (init := acc) fun acc mentsuList =>
        let shape : WinningShape n :=
          { pair := .toitsu tile, mentsu := mentsuListToFunction n mentsuList }
        (componentIndices n).foldl (init := acc) fun acc selected =>
          ((shape.component selected).tiles.dedup).foldl (init := acc) fun acc wait =>
            let seed : Seed n := { shape, selected, wait }
            if h : seed.valid = true then f acc ⟨seed, h⟩ else acc

open DirectWaitGeneration in
/-- Monadic variant used to stream canonical derivations without retaining them in memory. -/
def foldCanonicalDirectWaitDerivationsForPairTilesM {n : Nat} {α : Type} {m : Type → Type}
    [Monad m] (pairTiles : List Tile) (init : α) (f : α → WaitDerivation n → m α) : m α :=
  pairTiles.foldlM (init := init) fun acc tile =>
    (WaitDecompositionCode.combinationsWithRepetitionOver canonicalMentsuAlphabet n).foldlM
      (init := acc) fun acc mentsuList =>
        let shape : WinningShape n :=
          { pair := .toitsu tile, mentsu := mentsuListToFunction n mentsuList }
        (componentIndices n).foldlM (init := acc) fun acc selected =>
          ((shape.component selected).tiles.dedup).foldlM (init := acc) fun acc wait =>
            let seed : Seed n := { shape, selected, wait }
            if h : seed.valid = true then f acc ⟨seed, h⟩ else pure acc

open DirectWaitGeneration in
/--
面子の並べ替えだけが違う重複や、生成結果全体を並べた中間 `List` を保持せず、すべての雀頭牌の
正規化済み `WaitDerivation` を畳み込む。
-/
def foldCanonicalDirectWaitDerivations {n : Nat} {α : Type}
    (init : α) (f : α → WaitDerivation n → α) : α :=
  foldCanonicalDirectWaitDerivationsForPairTiles Tile.all init f

/--
面子の並べ替えだけが違う重複を生成しない、`directWaitDerivations` と同じ牌姿・待ちの集合を
ストリーミングで集約する。中間の `List (WaitDerivation n)` を保持せず、牌姿キーのハッシュマップへ
1件ずつ反映するため、ピークメモリは牌姿の重複除去後の件数に比例する。
-/
structure CanonicalGenerationResult where
  groups : List WaitCompletionGroup
  enumeratedDerivations : Nat
deriving BEq, DecidableEq, Repr

def canonicalWaitCompletionGroups (n : Nat) : CanonicalGenerationResult :=
  let (groups, count) :=
    foldCanonicalDirectWaitDerivations (n := n)
      ((∅ : Std.HashMap Nat WaitCompletionGroup), 0)
      fun (groups, count) derivation =>
        let tiles := DirectWaitGeneration.hand derivation
        let completion := DirectWaitGeneration.completion derivation
        let key := tileMultisetKey tiles
        let groups' :=
          match groups.get? key with
          | none => groups.insert key { tiles, completions := [completion] }
          | some existing =>
              groups.insert key
                { existing with completions := insertCompletion completion existing.completions }
        (groups', count + 1)
  { groups := groups.values, enumeratedDerivations := count }

/--
`WaitDecompositionCode.canReduceMentsuPreservingWaitCores` と同じ判定を、元の手牌ぶんの
待ち核だけレポート側がすでに持っている `completions` から求め直し、探索を省略する版。

`canReduceMentsuPreservingWaitCores` は元の手牌の待ち核を `WaitCompletionFinder.findWaitCompletions`
で毎回ゼロから探索し直すが、直接生成のレポートは同じ内容を `WaitCompletionGroup.completions` として
すでに持っている。そこから `WaitDecompositionCode.waitCores` で直接求めれば、元の手牌ぶんの
組合せ探索（`winningPartitions`）を省略できる。面子除去後の手牌は既知データがないため、
そちらは引き続き `WaitDecompositionCode.findWaitCores` で探索する。
-/
def canReduceMentsuPreservingWaitCoresGivenCompletions
    (tiles : List Tile) (completions : List WaitCompletion) : Bool :=
  let originalCores := WaitDecompositionCode.waitCores completions
  1 < tiles.length &&
    !(WaitCompletionFinder.mentsuReductions tiles |>.filter fun remaining =>
        !(WaitCompletionFinder.waitingTiles remaining).isEmpty &&
          WaitDecompositionCode.findWaitCores remaining == originalCores).isEmpty

/-- 除去後の牌姿から得た待ち核集合を、牌姿キーで再利用するキャッシュ。 -/
structure WaitCoreCache where
  values : Std.HashMap Nat (Option (List Nat))
  hits : Nat
  misses : Nat

def emptyWaitCoreCache : WaitCoreCache :=
  { values := ∅, hits := 0, misses := 0 }

private def insertCachedWaitCoreKeys
    (key : Nat) (cores : Option (List Nat)) (cache : WaitCoreCache) : WaitCoreCache :=
  { cache with values := cache.values.insert key cores }

private def cachedWaitCores
    (tiles : List Tile) (cache : WaitCoreCache) :
  Option (List Nat) × WaitCoreCache :=
  let key := tileMultisetKey tiles
  match cache.values.get? key with
  | some cores =>
      (cores, { cache with hits := cache.hits + 1 })
  | none =>
      let completions := WaitCompletionFinder.findWaitCompletions tiles
      let cores := if completions.isEmpty then none
        else some (WaitDecompositionCode.waitCoreKeys (WaitDecompositionCode.waitCores completions))
      (cores, { cache with
        misses := cache.misses + 1 } |> insertCachedWaitCoreKeys key cores)

def canReduceMentsuPreservingWaitCoreKeysWith {m : Type → Type} [Monad m]
    (tiles : List Tile) (completions : List WaitCompletion)
    (lookup : List Tile → m (Option (List Nat))) : m Bool := do
  let originalCores := WaitDecompositionCode.waitCoreKeys (WaitDecompositionCode.waitCores completions)
  let rec loop : List (List Tile) → m Bool
    | [] => pure false
    | remaining :: rest => do
        match ← lookup remaining with
        | some cores =>
            if cores == originalCores then pure true else loop rest
        | none => loop rest
  if 1 < tiles.length then loop (WaitCompletionFinder.mentsuReductions tiles)
  else pure false

/-- 既知の元手牌の完成情報を使い、除去後の待ち核探索だけをキャッシュする判定。 -/
def canReduceMentsuPreservingWaitCoresCached
    (tiles : List Tile) (completions : List WaitCompletion)
    (cache : WaitCoreCache) : Bool × WaitCoreCache :=
  let computation : StateM WaitCoreCache Bool :=
    canReduceMentsuPreservingWaitCoreKeysWith tiles completions fun remaining =>
      get >>= fun cache =>
      let (cores, cache) := cachedWaitCores remaining cache
      set cache *> pure cores
  computation.run cache

/-- 完成情報群に現れる待ち牌を、初出順で重複なく取り出す。 -/
def waitsFromCompletions (completions : List WaitCompletion) : List Tile :=
  (completions.map fun completion => completion.wait).eraseDups

/-- 同じ待ち分解コード列を持つ牌姿の件数と代表例。 -/
structure WaitDecompositionCodeGroup where
  codes : List Nat
  count : Nat
  representativeTiles : List Tile
  representativeWaits : List Tile
deriving BEq, DecidableEq, Repr

/-- 待ち分解コード列が一致するグループへ牌姿を1件加える。 -/
def addWaitDecompositionCodeGroup
    (codes : List Nat) (tiles waits : List Tile) :
    List WaitDecompositionCodeGroup → List WaitDecompositionCodeGroup
  | [] => [{ codes, count := 1, representativeTiles := tiles, representativeWaits := waits }]
  | group :: rest =>
      if group.codes == codes then
        { group with count := group.count + 1 } :: rest
      else
        group :: addWaitDecompositionCodeGroup codes tiles waits rest

/-- 各値を待ち分解コード列でまとめ、件数と最初の代表例を保持する。 -/
def groupByWaitDecompositionCodes {α : Type}
    (codes : α → List Nat) (tiles waits : α → List Tile) (values : List α) :
    List WaitDecompositionCodeGroup :=
  values.foldl
    (fun groups value => addWaitDecompositionCodeGroup
      (codes value) (tiles value) (waits value) groups)
    []

/-- Irreducible hands grouped by both their decomposition codes and component relations. -/
structure WaitDecompositionRelationGroup where
  codes : List Nat
  relationKey : List Nat
  count : Nat
  representativeTiles : List Tile
  representativeWaits : List Tile
  relationDescription : String
deriving BEq, DecidableEq, Repr

private def componentRelationKey (relation : ComponentRelation) : Nat :=
  let tileRelationKey := match relation.tileRelation with
    | .overlapping => 0
    | .disjoint => 1
    | .invalidComponents => 2
  (WaitComponentKind.all.idxOf relation.firstKind * WaitComponentKind.count +
      WaitComponentKind.all.idxOf relation.secondKind) * 3 + tileRelationKey

/-- Stable key for a complete wait-decomposition relation classification. -/
def waitDecompositionRelationKey
    (classification : WaitDecompositionRelationClassification) : List Nat :=
  [classification.signatures.length] ++
    classification.signatures.flatMap fun signature =>
      [signature.code, signature.relations.length] ++
        signature.relations.map componentRelationKey

private def componentKindName : WaitComponentKind → String
  | .tanki => "tanki"
  | .toitsu => "toitsu"
  | .ryanmen => "ryanmen"
  | .kanchan => "kanchan"
  | .penchan => "penchan"
  | .shuntsu => "shuntsu"
  | .koutsu => "koutsu"

/-- Human-readable per-code component relations, including whether tiles are disjoint. -/
def waitDecompositionRelationDescription
    (classification : WaitDecompositionRelationClassification) : String :=
  String.intercalate " | " <| classification.signatures.map fun signature =>
    s!"{signature.code}: " ++ String.intercalate ", " (signature.relations.map fun relation =>
      let tileRelation := match relation.tileRelation with
        | .overlapping => "overlapping"
        | .disjoint => "disjoint"
        | .invalidComponents => "invalid"
      s!"{componentKindName relation.firstKind}-{componentKindName relation.secondKind}={tileRelation}")

/-- Whether a classification contains at least one disjoint component relation. -/
def hasDisjointComponentRelation
    (classification : WaitDecompositionRelationClassification) : Bool :=
  classification.signatures.any fun signature =>
    signature.relations.any fun relation => relation.tileRelation == .disjoint

/-- Add one hand to the group with matching codes and component-relation key. -/
def addWaitDecompositionRelationGroup (codes relationKey : List Nat)
    (tiles waits : List Tile) (description : String) :
    List WaitDecompositionRelationGroup → List WaitDecompositionRelationGroup
  | [] => [{
      codes, relationKey, count := 1, representativeTiles := tiles,
      representativeWaits := waits, relationDescription := description
    }]
  | group :: rest =>
      if group.codes == codes && group.relationKey == relationKey then
        { group with count := group.count + 1 } :: rest
      else
        group :: addWaitDecompositionRelationGroup codes relationKey tiles waits description rest

/-- Merge relation groups while retaining the first representative of each group. -/
def mergeWaitDecompositionRelationGroups
    (groups additions : List WaitDecompositionRelationGroup) :
    List WaitDecompositionRelationGroup :=
  additions.foldl (fun merged addition =>
    let rec add : List WaitDecompositionRelationGroup → List WaitDecompositionRelationGroup
      | [] => [addition]
      | group :: rest =>
          if group.codes == addition.codes && group.relationKey == addition.relationKey then
            { group with count := group.count + addition.count } :: rest
          else
            group :: add rest
    add merged) groups

/-- 自然数キーの度数表へ1件加える。 -/
def incrementCount (key : Nat) : List (Nat × Nat) → List (Nat × Nat)
  | [] => [(key, 1)]
  | entry :: rest =>
      if entry.1 == key then
        (entry.1, entry.2 + 1) :: rest
      else
        entry :: incrementCount key rest

/-- 自然数列を初出順の度数表へ変換する。 -/
def countOccurrences (values : List Nat) : List (Nat × Nat) :=
  values.foldl (fun counts value => incrementCount value counts) []

private def formatNumberedGroup
    (tiles : List Tile) (suit : Suit) (suffix : String) : String :=
  let digits := (List.ofFn fun rank : Rank => rank).flatMap fun rank =>
    List.replicate (tiles.count (.numbered suit rank)) (toString (rank.val + 1))
  if digits.isEmpty then "" else String.join digits ++ suffix

private def formatHonorGroup (tiles : List Tile) : String :=
  let digits := Honor.all.flatMap fun honor =>
    List.replicate (tiles.count (.honor honor)) (toString (honor.orderKey + 1))
  if digits.isEmpty then "" else String.join digits ++ "z"

/-- 牌種列をスートごとにまとめた省略表記へ変換する。 -/
def formatTiles (tiles : List Tile) : String :=
  String.join <| [
    formatNumberedGroup tiles .Manzu "m",
    formatNumberedGroup tiles .Pinzu "p",
    formatNumberedGroup tiles .Souzu "s",
    formatHonorGroup tiles
  ].filter fun group => !group.isEmpty

/-- 待ち分解コードグループをレポートのTSV行へ変換する。 -/
def formatWaitDecompositionCodeGroup (group : WaitDecompositionCodeGroup) : String :=
  String.intercalate "\t" [
    toString group.codes,
    toString (WaitDecompositionCode.waitDecompositionCodesKey group.codes),
    toString group.count,
    formatTiles group.representativeTiles,
    formatTiles group.representativeWaits
  ]

/-- 待ち牌種類数の度数をレポート行へ変換する。 -/
def formatWaitTileCount (counts : List (Nat × Nat)) (waitTileCount : Nat) : String :=
  let count := (counts.find? fun entry => entry.1 == waitTileCount).map Prod.snd |>.getD 0
  s!"{waitTileCount} wait tile kinds: {count}"

end MahjongComputations
