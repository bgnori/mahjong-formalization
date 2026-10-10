import MahjongComputations.TenTileLegacy
import MahjongComputations.ReportJson

/-!
# Ten-tile sharded report generator

Run individual shards with `lake build ten-tile-shard-report-gen -- --shard=i --num-shards=k`.
-/

namespace MahjongComputations.TenTileShardReport

open MahjongComputations.TenTile
open MahjongComputations.ReportJson
open Lean

private def reportJson (summary : TenTileSummary) (elapsedMs : Nat) : Json :=
  report 10 elapsedMs ([
    ("allTileShapes", natural summary.allTenTileShapes),
    ("enumeratedDerivations", natural summary.enumeratedDerivations),
    ("tenpaiReports", natural summary.tenpaiReports),
    ("waitCoreCache", object [
      ("hits", natural summary.waitCoreCacheHits),
      ("misses", natural summary.waitCoreCacheMisses),
      ("entries", natural summary.waitCoreCacheEntries)
    ])
  ] ++ commonSummaryFields summary.irreducibleGroups summary.irreducibleRelationGroups
      summary.reducibleReports summary.irreducibleReports summary.irreducibleDisjointReports)
    (commonDataFields summary.irreducibleGroups summary.irreducibleRelationGroups
      summary.waitTileCountDistribution)

def parseArgs (args : List String) : Option (Nat × Nat × String) := do
  let mut shardIndex : Option Nat := none
  let mut numShards : Option Nat := none
  let mut outputPath : Option String := none
  for arg in args do
    if arg.startsWith "--shard=" then
      let idx := arg.drop 8
      shardIndex := idx.toNat?
    else if arg.startsWith "--num-shards=" then
      let num := arg.drop 13
      numShards := num.toNat?
    else if !arg.startsWith "--" then
      outputPath := some arg
  (·, ·, ·) <$> shardIndex <*> numShards <*> outputPath

def run (args : List String) : IO UInt32 := do
  match parseArgs args with
  | none =>
      IO.eprintln "usage: ten-tile-shard-report-gen [--shard=i] [--num-shards=k] [output.json]"
      return 1
  | some (shardIndex, numShards, outputPath) =>
      let path : System.FilePath := outputPath
      if let some parent := path.parent then
        IO.FS.createDirAll parent
      let started ← IO.monoMsNow
      let computedSummary := summaryWithShard shardIndex numShards
      let finished ← IO.monoMsNow
      IO.FS.writeFile path (encode (reportJson computedSummary (finished - started)))
      IO.println s!"wrote {path}"
      return 0

end MahjongComputations.TenTileShardReport

def main (args : List String) : IO UInt32 :=
  MahjongComputations.TenTileShardReport.run args
