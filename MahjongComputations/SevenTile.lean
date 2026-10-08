import Mahjong.DirectWaitGeneration
import Mahjong.WaitDecompositionCode
import MahjongComputations.Common
import MahjongComputations.Parallel

/-!
# Seven-tile wait computation from direct derivations

This module enumerates valid two-mentsu derivations, projects them to seven-tile
hands, and folds the resulting tenpai hands into summary data.  The total number
of legal seven-tile multisets is counted separately, without materializing the
non-tenpai shapes.
-/

namespace MahjongComputations.SevenTile

open DirectWaitGeneration
open WaitCompletionFinder
open WaitDecompositionCode

/-- Aggregated exhaustive report data for seven-tile shapes. -/
structure SevenTileSummary where
  allSevenTileShapes : Nat
  enumeratedDerivations : Nat
  tenpaiReports : Nat
  reducibleReports : Nat
  irreducibleReports : Nat
  waitCoreCacheHits : Nat
  waitCoreCacheMisses : Nat
  waitCoreCacheEntries : Nat
  irreducibleGroups : List WaitDecompositionCodeGroup
  irreducibleRelationClassifications : List WaitDecompositionRelationClassification
  waitTileCountDistribution : List (Nat × Nat)
deriving BEq, DecidableEq, Repr

private def emptySummary : SevenTileSummary :=
  { allSevenTileShapes := 0
    enumeratedDerivations := 0
    tenpaiReports := 0
    reducibleReports := 0
    irreducibleReports := 0
    waitCoreCacheHits := 0
    waitCoreCacheMisses := 0
    waitCoreCacheEntries := 0
    irreducibleGroups := []
    irreducibleRelationClassifications := []
    waitTileCountDistribution := [] }

private def allSevenTileShapeCount (_ : Unit) : Nat :=
  countLegalTileMultisetsOfLength 7 Tile.all

private structure ComputationState where
  summary : SevenTileSummary
  waitCoreCache : WaitCoreCache

private def insertRelationClassification
    (classification : WaitDecompositionRelationClassification)
    (classifications : List WaitDecompositionRelationClassification) :
    List WaitDecompositionRelationClassification :=
  if classifications.contains classification then classifications else classification :: classifications

private def addShapeReport (report : WaitCompletionGroup) (state : ComputationState) :
    ComputationState :=
  let completions := report.completions
  let waits := waitsFromCompletions completions
  let codes := waitDecompositionCodes completions
  let relationClassification := waitDecompositionRelationClassification completions
  let (reducible, waitCoreCache) :=
    canReduceMentsuPreservingWaitCoresCached report.tiles completions state.waitCoreCache
  let summary :=
    { state.summary with
      tenpaiReports := state.summary.tenpaiReports + 1
      waitTileCountDistribution :=
        incrementCount waits.length state.summary.waitTileCountDistribution }
  let summary := if reducible then
    { summary with reducibleReports := summary.reducibleReports + 1 }
  else
    { summary with
      irreducibleReports := summary.irreducibleReports + 1
      irreducibleGroups := addWaitDecompositionCodeGroup codes report.tiles waits summary.irreducibleGroups
      irreducibleRelationClassifications :=
        insertRelationClassification relationClassification
          summary.irreducibleRelationClassifications }
  { summary, waitCoreCache }

private def addShapeReportShared (cache : SharedWaitCoreCache)
    (summary : SevenTileSummary) (report : WaitCompletionGroup) : BaseIO SevenTileSummary := do
  let completions := report.completions
  let waits := waitsFromCompletions completions
  let codes := waitDecompositionCodes completions
  let relationClassification := waitDecompositionRelationClassification completions
  let reducible ← canReduceMentsuPreservingWaitCoresShared report.tiles completions cache
  let summary :=
    { summary with
      tenpaiReports := summary.tenpaiReports + 1
      waitTileCountDistribution := incrementCount waits.length summary.waitTileCountDistribution }
  if reducible then
    return { summary with reducibleReports := summary.reducibleReports + 1 }
  else
    return { summary with
      irreducibleReports := summary.irreducibleReports + 1
      irreducibleGroups := addWaitDecompositionCodeGroup codes report.tiles waits summary.irreducibleGroups
      irreducibleRelationClassifications :=
        insertRelationClassification relationClassification
          summary.irreducibleRelationClassifications }

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

private def mergeSummary (first second : SevenTileSummary) : SevenTileSummary :=
  { first with
    tenpaiReports := first.tenpaiReports + second.tenpaiReports
    reducibleReports := first.reducibleReports + second.reducibleReports
    irreducibleReports := first.irreducibleReports + second.irreducibleReports
    irreducibleGroups := second.irreducibleGroups.foldl addCodeGroup first.irreducibleGroups
    irreducibleRelationClassifications :=
      second.irreducibleRelationClassifications.foldl
        (fun classifications classification =>
          insertRelationClassification classification classifications)
        first.irreducibleRelationClassifications
    waitTileCountDistribution :=
      second.waitTileCountDistribution.foldl addDistribution first.waitTileCountDistribution }

/-- Exhaustive seven-tile aggregate summary. -/
def summary (_ : Unit) : SevenTileSummary :=
  let generated := canonicalWaitCompletionGroups 2
  let computed :=
    generated.groups.foldl (fun state report => addShapeReport report state)
      { summary := emptySummary, waitCoreCache := emptyWaitCoreCache }
  { computed.summary with
    allSevenTileShapes := allSevenTileShapeCount ()
    enumeratedDerivations := generated.enumeratedDerivations
    waitCoreCacheHits := computed.waitCoreCache.hits
    waitCoreCacheMisses := computed.waitCoreCache.misses
    waitCoreCacheEntries := computed.waitCoreCache.values.size }

/-- Exhaustive seven-tile summary classified concurrently with one shared wait-core cache. -/
def summaryParallel (workers : Nat) : BaseIO SevenTileSummary := do
  let generated := canonicalWaitCompletionGroups 2
  let cache ← SharedWaitCoreCache.new
  let partials ← parallelMapChunks workers generated.groups fun reports =>
    reports.foldlM (addShapeReportShared cache) emptySummary
  let computed := partials.foldl mergeSummary emptySummary
  let stats ← cache.stats
  return { computed with
    allSevenTileShapes := allSevenTileShapeCount ()
    enumeratedDerivations := generated.enumeratedDerivations
    waitCoreCacheHits := stats.hits
    waitCoreCacheMisses := stats.misses
    waitCoreCacheEntries := stats.entries }

example : countLegalTileMultisetsOfLength 7 Tile.all = 18623330 := by
  native_decide

end MahjongComputations.SevenTile
