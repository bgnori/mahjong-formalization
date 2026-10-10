import MahjongComputations.TenTile
import MahjongComputations.Parallel
import MahjongComputations.ReportJson

/-!
# Ten-tile report generator

Run through Lake with `lake build tenTileReport`.
-/

namespace MahjongComputations.TenTileReport

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
    ])]
      ++ commonSummaryFields summary.irreducibleGroups summary.irreducibleRelationGroups
        summary.reducibleReports summary.irreducibleReports summary.irreducibleDisjointReports)
    (commonDataFields summary.irreducibleGroups summary.irreducibleRelationGroups
      summary.waitTileCountDistribution)

def run (args : List String) : IO UInt32 := do
  IO.eprintln "ten-tile: parsing arguments"
  let (workers, outputPath) ←
    MahjongComputations.parseWorkerArgs args "reports/ten-tile-report.json"
  IO.eprintln s!"ten-tile: configured {workers} workers"
  let path : System.FilePath := outputPath
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  let started ← IO.monoMsNow
  let workDirectory : System.FilePath := ".lake/build/ten-tile-buckets"
  let computedSummary ← summaryParallel workers workDirectory
  let finished ← IO.monoMsNow
  IO.FS.writeFile path (encode (reportJson computedSummary (finished - started)))
  IO.println s!"wrote {path}"
  return 0

end MahjongComputations.TenTileReport

def main (args : List String) : IO UInt32 :=
  MahjongComputations.TenTileReport.run args
