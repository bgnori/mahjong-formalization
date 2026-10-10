import Mahjong.WaitDecompositionCode
import MahjongComputations.Common
import MahjongComputations.Parallel
import MahjongComputations.ExternalWaitCompletion

/-!
# Resumable external bucket classification

Each bucket's classification totals are persisted next to the bucket file, so an
interrupted run resumes without reclassifying the buckets it already finished.

Only per-bucket totals are persisted. Wait-core cache statistics describe the
process that computed them, so a resumed run reports the cache behaviour of that
run rather than of an uninterrupted one.
-/

namespace MahjongComputations.BucketClassification

open WaitCompletionFinder
open WaitDecompositionCode
open MahjongComputations

/-- Counts of irreducible hands with the same component-relation classification. -/
structure WaitDecompositionRelationGroup where
  codes : List Nat
  relationKey : List Nat
  count : Nat
  representativeTiles : List Tile
  representativeWaits : List Tile
  relationDescription : String
deriving BEq, DecidableEq, Repr

/-- Classification totals contributed by one or more buckets. -/
structure BucketSummary where
  tenpaiReports : Nat
  reducibleReports : Nat
  irreducibleReports : Nat
  irreducibleDisjointReports : Nat
  irreducibleGroups : List WaitDecompositionCodeGroup
  irreducibleRelationGroups : List WaitDecompositionRelationGroup
  waitTileCountDistribution : List (Nat × Nat)
deriving BEq, DecidableEq, Repr

/-- Totals before any bucket has been classified. -/
def empty : BucketSummary :=
  { tenpaiReports := 0
    reducibleReports := 0
    irreducibleReports := 0
    irreducibleDisjointReports := 0
    irreducibleGroups := []
    irreducibleRelationGroups := []
    waitTileCountDistribution := [] }

private def addCodeGroup
    (groups : List WaitDecompositionCodeGroup) (addition : WaitDecompositionCodeGroup) :
    List WaitDecompositionCodeGroup :=
  match groups with
  | [] => [addition]
  | group :: rest =>
      if group.codes == addition.codes then
        { group with count := group.count + addition.count } :: rest
      else
        group :: addCodeGroup rest addition

private def addDistribution
    (counts : List (Nat × Nat)) (addition : Nat × Nat) : List (Nat × Nat) :=
  match counts with
  | [] => [addition]
  | count :: rest =>
      if count.1 == addition.1 then
        (count.1, count.2 + addition.2) :: rest
      else
        count :: addDistribution rest addition

private def componentRelationKey (relation : ComponentRelation) : Nat :=
  let tileRelationKey := match relation.tileRelation with
    | .overlapping => 0
    | .disjoint => 1
    | .invalidComponents => 2
  (WaitComponentKind.all.idxOf relation.firstKind * WaitComponentKind.count +
      WaitComponentKind.all.idxOf relation.secondKind) * 3 + tileRelationKey

private def relationClassificationKey
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

private def relationDescription
    (classification : WaitDecompositionRelationClassification) : String :=
  String.intercalate " | " <| classification.signatures.map fun signature =>
    s!"{signature.code}: " ++ String.intercalate ", " (signature.relations.map fun relation =>
      let tileRelation := match relation.tileRelation with
        | .overlapping => "overlapping"
        | .disjoint => "disjoint"
        | .invalidComponents => "invalid"
      s!"{componentKindName relation.firstKind}-{componentKindName relation.secondKind}={tileRelation}")

private def hasDisjointRelation
    (classification : WaitDecompositionRelationClassification) : Bool :=
  classification.signatures.any fun signature =>
    signature.relations.any fun relation => relation.tileRelation == .disjoint

private def addRelationGroup (codes : List Nat) (relationKey : List Nat)
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
        group :: addRelationGroup codes relationKey tiles waits description rest

private def addRelationGroupCount (addition : WaitDecompositionRelationGroup) :
    List WaitDecompositionRelationGroup → List WaitDecompositionRelationGroup
  | [] => [addition]
  | group :: rest =>
      if group.codes == addition.codes && group.relationKey == addition.relationKey then
        { group with count := group.count + addition.count } :: rest
      else
        group :: addRelationGroupCount addition rest

private def mergeRelationGroups
    (groups : List WaitDecompositionRelationGroup)
    (additions : List WaitDecompositionRelationGroup) :
    List WaitDecompositionRelationGroup :=
  additions.foldl (fun merged addition => addRelationGroupCount addition merged) groups

/-- Combine two summaries, keeping the first occurrence order of groups and counts. -/
def merge (first second : BucketSummary) : BucketSummary :=
  { tenpaiReports := first.tenpaiReports + second.tenpaiReports
    reducibleReports := first.reducibleReports + second.reducibleReports
    irreducibleReports := first.irreducibleReports + second.irreducibleReports
    irreducibleDisjointReports :=
      first.irreducibleDisjointReports + second.irreducibleDisjointReports
    irreducibleGroups := second.irreducibleGroups.foldl addCodeGroup first.irreducibleGroups
    irreducibleRelationGroups :=
      mergeRelationGroups first.irreducibleRelationGroups second.irreducibleRelationGroups
    waitTileCountDistribution :=
      second.waitTileCountDistribution.foldl addDistribution first.waitTileCountDistribution }

/-- Fold one hand's wait completions into a classification summary. -/
def addShapeReport (cache : SharedWaitCoreCache)
    (summary : BucketSummary) (report : WaitCompletionGroup) : IO BucketSummary := do
  let completions := report.completions
  let waits := waitsFromCompletions completions
  let codes := waitDecompositionCodes completions
  let relationClassification := waitDecompositionRelationClassification completions
  let relationKey := relationClassificationKey relationClassification
  let relationDescription := relationDescription relationClassification
  let reducible ← liftM <| canReduceMentsuPreservingWaitCoresShared report.tiles completions cache
  let summary :=
    { summary with
      tenpaiReports := summary.tenpaiReports + 1
      waitTileCountDistribution := incrementCount waits.length summary.waitTileCountDistribution }
  if reducible then
    return { summary with reducibleReports := summary.reducibleReports + 1 }
  else
    return { summary with
      irreducibleReports := summary.irreducibleReports + 1
      irreducibleDisjointReports :=
        summary.irreducibleDisjointReports +
          if hasDisjointRelation relationClassification then 1 else 0
      irreducibleGroups :=
        addWaitDecompositionCodeGroup codes report.tiles waits summary.irreducibleGroups
      irreducibleRelationGroups :=
        addRelationGroup codes relationKey report.tiles waits relationDescription
          summary.irreducibleRelationGroups }

private def formatMagic : String := "MJWC-CLASSIFICATION-3"

private def encodeNats (values : List Nat) : String :=
  String.intercalate "," (values.map toString)

private def decodeNats (value : String) : Option (List Nat) :=
  if value.isEmpty then some [] else (value.splitOn ",").mapM String.toNat?

private def encodeTiles (tiles : List Tile) : String :=
  encodeNats (tiles.map fun tile => Tile.all.idxOf tile)

private def decodeTiles (value : String) : Option (List Tile) := do
  (← decodeNats value).mapM fun index => Tile.all[index]?

private def formatGroup (group : WaitDecompositionCodeGroup) : String :=
  String.intercalate "\t" [
    encodeNats group.codes,
    toString group.count,
    encodeTiles group.representativeTiles,
    encodeTiles group.representativeWaits
  ]

private def parseGroup (line : String) : Option WaitDecompositionCodeGroup := do
  match line.splitOn "\t" with
  | [codes, count, tiles, waits] =>
      return {
        codes := ← decodeNats codes
        count := ← count.toNat?
        representativeTiles := ← decodeTiles tiles
        representativeWaits := ← decodeTiles waits
      }
  | _ => none

private def formatRelationGroup (group : WaitDecompositionRelationGroup) : String :=
  String.intercalate "\t" [
    encodeNats group.codes,
    encodeNats group.relationKey,
    toString group.count,
    encodeTiles group.representativeTiles,
    encodeTiles group.representativeWaits,
    group.relationDescription
  ]

private def parseRelationGroup (line : String) : Option WaitDecompositionRelationGroup := do
  match line.splitOn "\t" with
  | [codes, relationKey, count, tiles, waits, description] =>
      return {
        codes := ← decodeNats codes
        relationKey := ← decodeNats relationKey
        count := ← count.toNat?
        representativeTiles := ← decodeTiles tiles
        representativeWaits := ← decodeTiles waits
        relationDescription := description
      }
  | _ => none

private def formatDistribution (entry : Nat × Nat) : String :=
  s!"{entry.1},{entry.2}"

private def parseDistribution (line : String) : Option (Nat × Nat) := do
  match line.splitOn "," with
  | [key, count] => return (← key.toNat?, ← count.toNat?)
  | _ => none

private def summaryText (mentsuCount : Nat) (summary : BucketSummary) : String :=
  String.intercalate "\n" <|
    [formatMagic,
     s!"mentsuCount={mentsuCount}",
     s!"tenpaiReports={summary.tenpaiReports}",
     s!"reducibleReports={summary.reducibleReports}",
     s!"irreducibleReports={summary.irreducibleReports}",
     s!"irreducibleDisjointReports={summary.irreducibleDisjointReports}",
     s!"groups={summary.irreducibleGroups.length}"] ++
    summary.irreducibleGroups.map formatGroup ++
    [s!"relationGroups={summary.irreducibleRelationGroups.length}"] ++
    summary.irreducibleRelationGroups.map formatRelationGroup ++
    [s!"distribution={summary.waitTileCountDistribution.length}"] ++
    summary.waitTileCountDistribution.map formatDistribution ++
    [""]

private def parseField (fieldPrefix value : String) : Option Nat := do
  guard (value.startsWith fieldPrefix)
  (value.drop fieldPrefix.length).toNat?

private def parseSummary (mentsuCount : Nat) (text : String) : Option BucketSummary := do
  let lines := text.splitOn "\n"
  guard (lines[0]? == some formatMagic)
  let savedMentsuCount ← lines[1]?.bind (parseField "mentsuCount=")
  guard (savedMentsuCount == mentsuCount)
  let tenpaiReports ← lines[2]?.bind (parseField "tenpaiReports=")
  let reducibleReports ← lines[3]?.bind (parseField "reducibleReports=")
  let irreducibleReports ← lines[4]?.bind (parseField "irreducibleReports=")
  let irreducibleDisjointReports ← lines[5]?.bind (parseField "irreducibleDisjointReports=")
  let groupCount ← lines[6]?.bind (parseField "groups=")
  let groupLines := (lines.drop 7).take groupCount
  guard (groupLines.length == groupCount)
  let irreducibleGroups ← groupLines.mapM parseGroup
  let relationGroupHeader := lines[7 + groupCount]?
  let relationGroupCount ← relationGroupHeader.bind (parseField "relationGroups=")
  let relationGroupLines := (lines.drop (8 + groupCount)).take relationGroupCount
  guard (relationGroupLines.length == relationGroupCount)
  let irreducibleRelationGroups ← relationGroupLines.mapM parseRelationGroup
  let remaining := lines.drop (8 + groupCount + relationGroupCount)
  let distributionCount ← remaining[0]?.bind (parseField "distribution=")
  let distributionLines := (remaining.drop 1).take distributionCount
  guard (distributionLines.length == distributionCount)
  let waitTileCountDistribution ← distributionLines.mapM parseDistribution
  return {
    tenpaiReports
    reducibleReports
    irreducibleReports
    irreducibleDisjointReports
    irreducibleGroups
    irreducibleRelationGroups
    waitTileCountDistribution
  }

/-- Stable path holding one bucket's saved classification result. -/
def resultPath (bucketPath : System.FilePath) : System.FilePath :=
  ⟨bucketPath.toString ++ ".result"⟩

/-- Read a saved classification result, ignoring one that does not match this layout. -/
def readResult (bucketPath : System.FilePath) (mentsuCount : Nat) :
    IO (Option BucketSummary) := do
  let path := resultPath bucketPath
  unless ← path.pathExists do return none
  return parseSummary mentsuCount (← IO.FS.readFile path)

/-- Atomically persist one bucket's classification result. -/
def writeResult (bucketPath : System.FilePath) (mentsuCount : Nat)
    (summary : BucketSummary) : IO Unit := do
  let path := resultPath bucketPath
  let partPath : System.FilePath := ⟨path.toString ++ ".part"⟩
  IO.FS.writeFile partPath (summaryText mentsuCount summary)
  IO.FS.rename partPath path

/-- Remove every saved classification result for a bucket set. -/
def clearResults (paths : List System.FilePath) : IO Unit :=
  paths.forM fun bucketPath => do
    for path in [resultPath bucketPath, ⟨(resultPath bucketPath).toString ++ ".part"⟩] do
      if ← path.pathExists then
        IO.FS.removeFile path

private def classifyBucket (cache : SharedWaitCoreCache) (mentsuCount : Nat)
    (path : System.FilePath) : IO BucketSummary := do
  if let some saved ← readResult path mentsuCount then
    IO.eprintln s!"bucket-classification: reusing {resultPath path}"
    return saved
  let groups ← ExternalWaitCompletion.readGroups path mentsuCount
  let summary ← groups.foldlM (addShapeReport cache) empty
  writeResult path mentsuCount summary
  return summary

/--
Classify every bucket with `workers` tasks, saving each bucket's totals so that a
later run skips the buckets it already completed.
-/
def classifyBuckets (workers mentsuCount : Nat) (cache : SharedWaitCoreCache)
    (paths : List System.FilePath) : IO BucketSummary := do
  let partials ← parallelMapChunksIO workers paths fun workerPaths =>
    workerPaths.foldlM (init := empty) fun summary path => do
      return merge summary (← classifyBucket cache mentsuCount path)
  return partials.foldl merge empty

end MahjongComputations.BucketClassification
