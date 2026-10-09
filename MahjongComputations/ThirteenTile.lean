import Mahjong.DirectWaitGeneration
import Mahjong.WaitDecompositionCode
import MahjongComputations.Common
import MahjongComputations.Parallel
import MahjongComputations.ExternalWaitCompletion
import MahjongComputations.BucketClassification

/-!
# Thirteen-tile wait computation from direct derivations

This module enumerates valid four-mentsu derivations, projects them to standard
thirteen-tile hands, and folds the resulting tenpai hands into summary data.  The
total number of legal thirteen-tile multisets is counted separately, without
materializing the non-tenpai shapes.
-/

namespace MahjongComputations.ThirteenTile

open DirectWaitGeneration
open WaitCompletionFinder
open WaitDecompositionCode
open MahjongComputations

/-- Aggregated exhaustive report data for thirteen-tile shapes. -/
structure ThirteenTileSummary where
  allThirteenTileShapes : Nat
  enumeratedDerivations : Nat
  tenpaiReports : Nat
  reducibleReports : Nat
  irreducibleReports : Nat
  waitCoreCacheHits : Nat
  waitCoreCacheMisses : Nat
  waitCoreCacheEntries : Nat
  irreducibleGroups : List WaitDecompositionCodeGroup
  waitTileCountDistribution : List (Nat × Nat)
deriving BEq, DecidableEq, Repr

private def emptySummary : ThirteenTileSummary :=
  { allThirteenTileShapes := 0
    enumeratedDerivations := 0
    tenpaiReports := 0
    reducibleReports := 0
    irreducibleReports := 0
    waitCoreCacheHits := 0
    waitCoreCacheMisses := 0
    waitCoreCacheEntries := 0
    irreducibleGroups := []
    waitTileCountDistribution := [] }

private def allThirteenTileShapeCount : Nat := 98521596000

/-- Summary plus whether generation reused a completed external bucket set. -/
structure ThirteenTileRunResult where
  summary : ThirteenTileSummary
  generationReused : Bool

private def generateBuckets (workers : Nat) (workDirectory : System.FilePath)
    (bucketCount : Nat) : IO (List System.FilePath × Nat × Bool) := do
  if let some derivationCount ←
      ExternalWaitCompletion.readGenerationCheckpoint workDirectory 4 bucketCount then
    IO.eprintln s!"thirteen-tile: reusing {derivationCount} generated derivations"
    return (ExternalWaitCompletion.bucketPaths workDirectory bucketCount, derivationCount, true)
  ExternalWaitCompletion.clearGenerationCheckpoint workDirectory
  BucketClassification.clearResults (ExternalWaitCompletion.bucketPaths workDirectory bucketCount)
  IO.eprintln s!"thirteen-tile: opening {bucketCount} buckets with {workers} generation workers"
  let generation ← ExternalWaitCompletion.withBucketSet workDirectory 4 bucketCount
    (action := fun buckets => do
      IO.eprintln "thirteen-tile: generating derivations"
      let counts ← parallelMapChunksIO workers Tile.all fun pairTiles =>
        foldCanonicalDirectWaitDerivationsForPairTilesM (n := 4) pairTiles 0
          fun count derivation => do
            buckets.append {
              tiles := DirectWaitGeneration.hand derivation
              completion := DirectWaitGeneration.completion derivation }
            pure (count + 1)
      return (buckets.paths, counts.sum))
  let (paths, derivationCount) := generation
  ExternalWaitCompletion.writeGenerationCheckpoint workDirectory 4 bucketCount derivationCount
  IO.eprintln s!"thirteen-tile: generated {derivationCount} derivations; checkpoint saved"
  return (paths, derivationCount, false)

/-- Generate or reuse external buckets, then classify them with a shared wait-core cache. -/
def summaryParallel (generationWorkers classificationWorkers : Nat)
    (workDirectory : System.FilePath) (bucketCount : Nat := 256) : IO ThirteenTileRunResult := do
  let (paths, enumeratedDerivations, generationReused) ←
    generateBuckets generationWorkers workDirectory bucketCount
  IO.eprintln s!"thirteen-tile: classifying {paths.length} buckets with {classificationWorkers} workers"
  let cache ← SharedWaitCoreCache.new
  let computed ← BucketClassification.classifyBuckets classificationWorkers 4 cache paths
  let stats ← liftM cache.stats
  return {
    summary := { emptySummary with
      allThirteenTileShapes := allThirteenTileShapeCount
      enumeratedDerivations
      tenpaiReports := computed.tenpaiReports
      reducibleReports := computed.reducibleReports
      irreducibleReports := computed.irreducibleReports
      waitCoreCacheHits := stats.hits
      waitCoreCacheMisses := stats.misses
      waitCoreCacheEntries := stats.entries
      irreducibleGroups := computed.irreducibleGroups
      waitTileCountDistribution := computed.waitTileCountDistribution }
    generationReused
  }

end MahjongComputations.ThirteenTile
