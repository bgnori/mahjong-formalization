import MahjongComputations.TenTile

/-!
# Legacy monolithic ten-tile computation

This module isolates the original in-memory shard implementation from the external-bucket report.
-/

namespace MahjongComputations.TenTile

open WaitCompletionFinder
open WaitDecompositionCode
open MahjongComputations

private def emptyLegacySummary : TenTileSummary :=
  { allTenTileShapes := 0
    enumeratedDerivations := 0
    tenpaiReports := 0
    reducibleReports := 0
    irreducibleReports := 0
    irreducibleDisjointReports := 0
    waitCoreCacheHits := 0
    waitCoreCacheMisses := 0
    waitCoreCacheEntries := 0
    irreducibleGroups := []
    irreducibleRelationGroups := []
    waitTileCountDistribution := [] }

private structure ComputationState where
  summary : TenTileSummary
  waitCoreCache : WaitCoreCache

private def addShapeReport (report : WaitCompletionGroup) (state : ComputationState) :
    ComputationState :=
  let completions := report.completions
  let waits := waitsFromCompletions completions
  let codes := waitDecompositionCodes completions
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
      irreducibleGroups := addWaitDecompositionCodeGroup codes report.tiles waits summary.irreducibleGroups }
  { summary, waitCoreCache }

@[noinline] private def allTenTileShapeCountLegacy (tileCount : Nat) : Nat :=
  countLegalTileMultisetsOfLength tileCount Tile.all

/-- Ten-tile summary using the original in-memory compact-key cache. -/
def summaryWithCache (shardIndex numShards : Nat) : TenTileSummary :=
  let generated := canonicalWaitCompletionGroups 3
  let filtered := generated.groups.filter fun group =>
    (tileMultisetKey group.tiles) % numShards == shardIndex
  let computed :=
    filtered.foldl (fun state report => addShapeReport report state)
      { summary := emptyLegacySummary
        waitCoreCache := emptyWaitCoreCache }
  { computed.summary with
    allTenTileShapes := allTenTileShapeCountLegacy 10
    enumeratedDerivations := generated.enumeratedDerivations
    waitCoreCacheHits := computed.waitCoreCache.hits
    waitCoreCacheMisses := computed.waitCoreCache.misses
    waitCoreCacheEntries := computed.waitCoreCache.values.size }

/-- Exhaustive ten-tile aggregate summary with optional legacy sharding. -/
def summaryWithShard (shardIndex : Nat := 0) (numShards : Nat := 1) : TenTileSummary :=
  summaryWithCache shardIndex numShards

end MahjongComputations.TenTile
