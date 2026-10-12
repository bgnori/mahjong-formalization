import MahjongComputations.Parallel
import MahjongComputations.ExternalWaitCompletion
import MahjongComputations.ThirteenTile
import MahjongComputations.FourTile
import MahjongComputations.SevenTile

namespace MahjongTests.ParallelComputation

open MahjongComputations
open WaitCompletionFinder

private def testHand : List Tile := manzu [0, 1, 2, 3]
private def otherHand : List Tile := manzu [3]

private def ensure (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def testPartitionedCanonicalGeneration : IO Unit := do
  let midpoint := Tile.all.length / 2
  let first := foldCanonicalDirectWaitDerivationsForPairTiles (n := 1)
    (Tile.all.take midpoint) [] fun derivations derivation => derivation :: derivations
  let second := foldCanonicalDirectWaitDerivationsForPairTiles (n := 1)
    (Tile.all.drop midpoint) [] fun derivations derivation => derivation :: derivations
  let full := foldCanonicalDirectWaitDerivations (n := 1) []
    fun derivations derivation => derivation :: derivations
  ensure (second ++ first == full)
    "partitioned canonical generation differs from full generation"
  let monadic ← foldCanonicalDirectWaitDerivationsForPairTilesM (n := 1) Tile.all []
    fun derivations derivation => pure (derivation :: derivations)
  ensure (monadic == full) "monadic canonical generation differs from pure generation"

private def testExternalRecordCodec : IO Unit := do
  let records := foldCanonicalDirectWaitDerivations (n := 1) []
    fun records derivation =>
      { tiles := DirectWaitGeneration.hand derivation
        completion := DirectWaitGeneration.completion derivation } :: records
  for record in records do
    let encoded := ExternalWaitCompletion.encode 1 record
    ensure encoded.isSome "failed to encode a valid four-tile derivation"
    ensure (encoded.bind (ExternalWaitCompletion.decode 1) == some record)
      "external wait-completion record failed to round trip"
  ensure (ExternalWaitCompletion.decode 1 ByteArray.empty).isNone
    "external codec accepted a truncated record"

private def testExternalBucketFile : IO Unit := do
  let path : System.FilePath := ".lake/build/parallel-computation-external-test.bin"
  let records := (foldCanonicalDirectWaitDerivations (n := 1) []
    fun records derivation =>
      { tiles := DirectWaitGeneration.hand derivation
        completion := DirectWaitGeneration.completion derivation } :: records).take 20
  try
    ExternalWaitCompletion.withWriter path 1 7 fun writer =>
      records.forM writer.append
    let decoded ← ExternalWaitCompletion.foldFile path 1 [] fun decoded record =>
      pure (record :: decoded)
    ensure (decoded.reverse == records) "external bucket changed record order or contents"
    IO.FS.withFile path .append fun handle =>
      handle.write (ByteArray.empty.push 0)
    let rejected ← try
      discard <| ExternalWaitCompletion.foldFile path 1 () fun _ _ => pure ()
      pure false
    catch _ => pure true
    ensure rejected "external bucket reader accepted a truncated final record"
  finally
    IO.FS.removeFile path

private def externalRecordKey (record : ExternalWaitCompletion.Record) : Nat :=
  (ExternalWaitCompletion.encode 1 record).get!.data.foldl
    (fun key byte => key * 128 + byte.toNat + 1) 0

private def testParallelBucketGeneration : IO Unit := do
  let directory : System.FilePath := ".lake/build/parallel-computation-buckets"
  let bucketCount := 4
  let paths := (List.range bucketCount).map (ExternalWaitCompletion.bucketPath directory)
  let expected := foldCanonicalDirectWaitDerivations (n := 1) [] fun records derivation =>
    { tiles := DirectWaitGeneration.hand derivation
      completion := DirectWaitGeneration.completion derivation } :: records
  try
    let generatedCount ← ExternalWaitCompletion.withBucketSet directory 1 bucketCount 14
      fun buckets => do
        let counts ← parallelMapChunksIO 4 Tile.all fun pairTiles =>
          foldCanonicalDirectWaitDerivationsForPairTilesM (n := 1) pairTiles 0
            fun count derivation => do
              buckets.append {
                tiles := DirectWaitGeneration.hand derivation
                completion := DirectWaitGeneration.completion derivation }
              pure (count + 1)
        pure counts.sum
    ensure (generatedCount == expected.length)
      "parallel external generation changed the derivation count"
    let decoded ← paths.foldlM (init := []) fun decoded path =>
      ExternalWaitCompletion.foldFile path 1 decoded fun records record =>
        pure (record :: records)
    let sortKeys := fun records =>
      (records.map externalRecordKey).mergeSort fun first second => decide (first ≤ second)
    ensure (sortKeys decoded == sortKeys expected)
      "parallel external buckets changed the derivation multiset"
    let grouped ← paths.flatMapM fun path => ExternalWaitCompletion.readGroups path 1
    let expectedGroups := (canonicalWaitCompletionGroups 1).groups.map
      (ExternalWaitCompletion.normalizeGroup 1)
    let sortGroups := fun groups => groups.mergeSort fun first second =>
      decide (tileMultisetKey first.tiles ≤ tileMultisetKey second.tiles)
    ensure (sortGroups grouped == sortGroups expectedGroups)
      "external bucket grouping differs from in-memory canonical grouping"
    ExternalWaitCompletion.writeGenerationCheckpoint directory 1 bucketCount generatedCount
    let checkpoint ← ExternalWaitCompletion.readGenerationCheckpoint directory 1 bucketCount
    ensure (checkpoint == some generatedCount) "external generation checkpoint did not round trip"
    let wrongCheckpoint ← ExternalWaitCompletion.readGenerationCheckpoint directory 1 (bucketCount + 1)
    ensure wrongCheckpoint.isNone "external generation checkpoint accepted different settings"
  finally
    ExternalWaitCompletion.clearGenerationCheckpoint directory
    paths.forM IO.FS.removeFile
    IO.FS.removeDir directory

private def testThirteenTileGenerationReuse : IO Unit := do
  let directory : System.FilePath := ".lake/build/thirteen-tile-checkpoint-test"
  let paths := ExternalWaitCompletion.bucketPaths directory 1
  try
    ExternalWaitCompletion.withBucketSet directory 4 1 (action := fun _ => pure ())
    ExternalWaitCompletion.writeGenerationCheckpoint directory 4 1 0
    let result ← ThirteenTile.summaryParallel 2 2 directory 1
    ensure result.generationReused "thirteen-tile pipeline did not reuse completed generation"
    ensure (result.summary.enumeratedDerivations == 0)
      "thirteen-tile pipeline changed the checkpoint derivation count"
    ensure (result.summary.tenpaiReports == 0)
      "empty thirteen-tile checkpoint produced reports"
    ensure (result.summary.allThirteenTileShapes == 98521596000)
      "unexpected thirteen-tile legal shape count"
  finally
    ExternalWaitCompletion.clearGenerationCheckpoint directory
    BucketClassification.clearResults paths
    paths.forM IO.FS.removeFile
    IO.FS.removeDir directory

private def testPathologyReports : IO Unit := do
  let (four, _) ← FourTile.directDerivationReportsParallel 2
  ensure (four == FourTile.directDerivationReportsWithCache.1)
    "four-tile pure and parallel classifications differ"
  ensure ((four.filter fun shape => shape.pathologyWitnesses.any
    (fun w => w.pathology == .redundantAmbiguity)).length == 27)
    "unexpected four-tile redundant ambiguity count"
  ensure (four.all fun shape => shape.pathologyWitnesses.all
    (fun w => w.pathology != .waitSuppression))
    "unexpected four-tile wait suppression"
  let seven ← SevenTile.summaryParallel 2
  ensure (seven == SevenTile.summary ())
    "seven-tile pure and parallel classifications differ"
  let count := fun kind => seven.pathologyGroups.foldl (fun total group =>
    total + if group.witness.pathology == kind then group.count else 0) 0
  ensure (count .waitSuppression == 126 && count .redundantAmbiguity == 3636)
    "unexpected seven-tile pathology counts"
  let pathologicalRelations := seven.irreducibleRelationGroups.filter fun group =>
    group.waitSuppressionCount > 0 || group.redundantAmbiguityCount > 0
  let mixedRelations := seven.irreducibleRelationGroups.filter fun group =>
    let healthy :=
      group.count -
        (group.waitSuppressionCount + group.redundantAmbiguityCount -
          group.bothPathologiesCount)
    [healthy, group.waitSuppressionCount - group.bothPathologiesCount,
      group.redundantAmbiguityCount - group.bothPathologiesCount,
      group.bothPathologiesCount].filter (· > 0) |>.length > 1
  ensure (pathologicalRelations.length == 27 && mixedRelations.isEmpty)
    "unexpected seven-tile relation-class pathology distribution"

private def testPathologyCheckpoint : IO Unit := do
  let path : System.FilePath := ".lake/build/pathology-checkpoint-test.bin"
  let tiles := manzu [0, 1, 1, 2]
  let group : WaitCompletionGroup := { tiles, completions := findWaitCompletions tiles }
  let cache ← SharedWaitCoreCache.new
  let summary ← BucketClassification.addShapeReport cache BucketClassification.empty group
  ensure (!summary.pathologyGroups.isEmpty) "checkpoint test needs a pathology witness"
  try
    BucketClassification.writeResult path 1 summary
    ensure ((← BucketClassification.readResult path 1) == some summary)
      "pathology checkpoint failed to round trip"
    ensure ((← BucketClassification.readResult path 2).isNone)
      "pathology checkpoint accepted a different mentsu count"
    IO.FS.writeFile (BucketClassification.resultPath path) "MJWC-CLASSIFICATION-3\n"
    ensure ((← BucketClassification.readResult path 1).isNone)
      "old classification checkpoint was reused without pathology data"
  finally
    BucketClassification.clearResults [path]

def run : IO UInt32 := do
  testPartitionedCanonicalGeneration
  testExternalRecordCodec
  testExternalBucketFile
  testParallelBucketGeneration
  testThirteenTileGenerationReuse
  testPathologyReports
  testPathologyCheckpoint
  let cache ← SharedWaitCoreCache.new
  let tasks ← (List.range 8).mapM fun _ =>
    BaseIO.asTask (do
      let threadId ← IO.getTID
      let result ← cache.lookup testHand
      return (threadId, result)) Task.Priority.dedicated
  let taskResults ← tasks.mapM fun task => BaseIO.toIO (IO.wait task)
  let threadIds := taskResults.map Prod.fst |>.eraseDups
  let results := taskResults.map Prod.snd
  ensure (threadIds.length > 1) s!"worker tasks used only one thread: {threadIds}"
  ensure (results.all fun result => result == results.head!)
    "concurrent cache lookups returned different results"
  let stats ← cache.stats
  ensure (stats == { hits := 7, misses := 1, entries := 1 })
    s!"unexpected concurrent cache stats: {repr stats}"

  let repeated ← cache.lookup testHand
  ensure (repeated == results.head!) "ready cache lookup changed its result"
  let stats ← cache.stats
  ensure (stats == { hits := 8, misses := 1, entries := 1 })
    s!"unexpected ready cache stats: {repr stats}"

  discard <| cache.lookup otherHand
  let stats ← cache.stats
  ensure (stats == { hits := 8, misses := 2, entries := 2 })
    s!"unexpected distinct-key cache stats: {repr stats}"
  IO.println "parallel wait-core cache tests passed"
  return 0

end MahjongTests.ParallelComputation

def main : IO UInt32 :=
  MahjongTests.ParallelComputation.run
