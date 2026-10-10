import Mahjong.DirectWaitGeneration
import Mahjong.WaitDecompositionCode
import MahjongComputations.Common
import MahjongComputations.Parallel
import MahjongComputations.ExternalWaitCompletion
import MahjongComputations.BucketClassification

/-!
# Ten-tile wait computation from direct derivations

This module enumerates valid three-mentsu derivations, projects them to ten-tile
hands, and folds the resulting tenpai hands into summary data.  The total number
of legal ten-tile multisets is counted separately, without materializing the
non-tenpai shapes.
-/

namespace MahjongComputations.TenTile

open DirectWaitGeneration
open WaitCompletionFinder
open WaitDecompositionCode
open MahjongComputations

/-- Aggregated exhaustive report data for ten-tile shapes. -/
structure TenTileSummary where
  allTenTileShapes : Nat
  enumeratedDerivations : Nat
  tenpaiReports : Nat
  reducibleReports : Nat
  irreducibleReports : Nat
  irreducibleDisjointReports : Nat
  waitCoreCacheHits : Nat
  waitCoreCacheMisses : Nat
  waitCoreCacheEntries : Nat
  irreducibleGroups : List WaitDecompositionCodeGroup
  irreducibleRelationGroups : List WaitDecompositionRelationGroup
  waitTileCountDistribution : List (Nat × Nat)
deriving BEq, DecidableEq, Repr

private def emptySummary : TenTileSummary :=
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

private def allTenTileShapeCount : Nat := 1900269316

private def generateBuckets (workers : Nat) (workDirectory : System.FilePath)
    (bucketCount : Nat) : IO (List System.FilePath × Nat) := do
  if let some derivationCount ←
      ExternalWaitCompletion.readGenerationCheckpoint workDirectory 3 bucketCount then
    IO.eprintln s!"ten-tile: reusing {derivationCount} generated derivations"
    return (ExternalWaitCompletion.bucketPaths workDirectory bucketCount, derivationCount)
  ExternalWaitCompletion.clearGenerationCheckpoint workDirectory
  BucketClassification.clearResults (ExternalWaitCompletion.bucketPaths workDirectory bucketCount)
  IO.eprintln s!"ten-tile: opening {bucketCount} buckets with {workers} workers"
  let generation ← ExternalWaitCompletion.withBucketSet workDirectory 3 bucketCount
    (action := fun buckets => do
      IO.eprintln "ten-tile: generating derivations"
      let counts ← parallelMapChunksIO workers Tile.all fun pairTiles =>
        foldCanonicalDirectWaitDerivationsForPairTilesM (n := 3) pairTiles 0
          fun count derivation => do
            buckets.append {
              tiles := DirectWaitGeneration.hand derivation
              completion := DirectWaitGeneration.completion derivation }
            pure (count + 1)
      return (buckets.paths, counts.sum))
  let (paths, derivationCount) := generation
  ExternalWaitCompletion.writeGenerationCheckpoint workDirectory 3 bucketCount derivationCount
  return (paths, derivationCount)

/-- Generate and classify ten-tile derivations through bounded external hash buckets. -/
def summaryParallel (workers : Nat) (workDirectory : System.FilePath)
    (bucketCount : Nat := 64) : IO TenTileSummary := do
  let (paths, enumeratedDerivations) ← generateBuckets workers workDirectory bucketCount
  IO.eprintln s!"ten-tile: generated {enumeratedDerivations} derivations; classifying buckets"
  let cache ← SharedWaitCoreCache.new
  let computed ← BucketClassification.classifyBuckets workers 3 cache paths
  let stats ← liftM cache.stats
  return { emptySummary with
    allTenTileShapes := allTenTileShapeCount
    enumeratedDerivations
    tenpaiReports := computed.tenpaiReports
    reducibleReports := computed.reducibleReports
    irreducibleReports := computed.irreducibleReports
    irreducibleDisjointReports := computed.irreducibleDisjointReports
    waitCoreCacheHits := stats.hits
    waitCoreCacheMisses := stats.misses
    waitCoreCacheEntries := stats.entries
    irreducibleGroups := computed.irreducibleGroups
    irreducibleRelationGroups := computed.irreducibleRelationGroups
    waitTileCountDistribution := computed.waitTileCountDistribution }

end MahjongComputations.TenTile
