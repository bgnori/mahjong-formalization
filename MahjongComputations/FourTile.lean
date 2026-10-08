import Mahjong.DirectWaitGeneration
import MahjongComputations.Common
import MahjongComputations.Parallel

/-!
# Exhaustive four-tile wait computation

This module is intentionally outside the `Mahjong` library.  It enumerates all
legal four-tile multisets and computes the wait information that is useful for
studying one-mentsu standard-form tenpai shapes.
-/

namespace MahjongComputations.FourTile

open DirectWaitGeneration
open WaitDecompositionCode
open WaitCompletionFinder
open MahjongComputations

/-- A computed summary for one four-tile shape. -/
structure FourTileShapeReport where
  tiles : List Tile
  waits : List Tile
  reducibility : Option WaitReducibility
  waitDecompositionCodes : List Nat
  relationClassification : WaitDecompositionRelationClassification
deriving BEq, DecidableEq, Repr

/-- All legal four-tile shapes as sorted tile-type multisets. -/
def allFourTileShapes : List (List Tile) :=
  legalTileMultisetsOfLength 4 Tile.all

/-- Computed wait report for a four-tile shape, including non-tenpai shapes. -/
def report (tiles : List Tile) : FourTileShapeReport :=
  { tiles
    waits := waitingTiles tiles
    reducibility := determineReducibility tiles
    waitDecompositionCodes := findWaitDecompositionCodes tiles
    relationClassification := findWaitDecompositionRelationClassification tiles }

/-- Exhaustive four-tile tenpai reports. -/
def tenpaiReports : List FourTileShapeReport :=
  (allFourTileShapes.map report).filter fun report => !report.waits.isEmpty

private def directFourTileGenerated : CanonicalGenerationResult :=
  canonicalWaitCompletionGroups 1

private def directReport (report : WaitCompletionGroup) : FourTileShapeReport :=
  let completions := report.completions
  { tiles := report.tiles
    waits := waitsFromCompletions completions
    reducibility := some (if canReduceMentsuPreservingWaitCoresGivenCompletions report.tiles completions
      then .reducible else .irreducible)
    waitDecompositionCodes := waitDecompositionCodes completions
    relationClassification := waitDecompositionRelationClassification completions }

/-- Four-tile direct reports computed with one cache shared by all shapes. -/
def directDerivationReportsWithCache :
  List FourTileShapeReport × MahjongComputations.WaitCoreCache :=
  let (reports, cache) := directFourTileGenerated.groups.foldl
    (fun (reports, cache) report =>
      let completions := report.completions
      let (reducible, cache) :=
        MahjongComputations.canReduceMentsuPreservingWaitCoresCached
          report.tiles completions cache
      let result : FourTileShapeReport :=
        { tiles := report.tiles
          waits := waitsFromCompletions completions
          reducibility := some (if reducible then .reducible else .irreducible)
          waitDecompositionCodes := waitDecompositionCodes completions
          relationClassification := waitDecompositionRelationClassification completions }
      (result :: reports, cache))
    ([], MahjongComputations.emptyWaitCoreCache)
  (reports.reverse, cache)

/-- Four-tile direct reports classified concurrently with one shared wait-core cache. -/
def directDerivationReportsParallel (workers : Nat) :
    BaseIO (List FourTileShapeReport × SharedWaitCoreCacheStats) := do
  let cache ← SharedWaitCoreCache.new
  let partials ← parallelMapChunks workers directFourTileGenerated.groups fun reports => do
    let reversed ← reports.foldlM (init := []) fun results report => do
      let completions := report.completions
      let reducible ← canReduceMentsuPreservingWaitCoresShared report.tiles completions cache
      let result : FourTileShapeReport :=
        { tiles := report.tiles
          waits := waitsFromCompletions completions
          reducibility := some (if reducible then .reducible else .irreducible)
          waitDecompositionCodes := waitDecompositionCodes completions
          relationClassification := waitDecompositionRelationClassification completions }
      return result :: results
    return reversed.reverse
  let stats ← cache.stats
  return (partials.flatten, stats)

/-- Number of normalized direct derivations enumerated for four-tile shapes. -/
def directDerivationCount : Nat :=
  directFourTileGenerated.enumeratedDerivations

/-- Four-tile tenpai reports computed by projecting direct derivations and grouping equal hands. -/
def directDerivationTenpaiReports : List FourTileShapeReport :=
  directFourTileGenerated.groups.map directReport

/-- Irreducible four-tile tenpai shapes. -/
def irreducibleReports : List FourTileShapeReport :=
  tenpaiReports.filter fun report => report.reducibility == some .irreducible

example : allFourTileShapes.length = 66045 := by
  native_decide

end MahjongComputations.FourTile
