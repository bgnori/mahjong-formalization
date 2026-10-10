import MahjongComputations.SevenTile
import MahjongComputations.Parallel
import MahjongComputations.ReportJson

/-!
# Seven-tile report generator

Run through Lake with `lake build sevenTileReport`.
-/

namespace MahjongComputations.SevenTileReport

open MahjongComputations.SevenTile
open MahjongComputations.ReportJson
open Lean

private def reportJson (summary : SevenTileSummary) (elapsedMs : Nat) : Json :=
  report 7 elapsedMs ([
    ("allTileShapes", natural summary.allSevenTileShapes),
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
  let (workers, outputPath) ←
    MahjongComputations.parseWorkerArgs args "reports/seven-tile-report.json"
  let path : System.FilePath := outputPath
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  let started ← IO.monoMsNow
  let computedSummary ← summaryParallel workers
  let finished ← IO.monoMsNow
  IO.FS.writeFile path (encode (reportJson computedSummary (finished - started)))
  IO.println s!"wrote {path}"
  return 0

end MahjongComputations.SevenTileReport

def main (args : List String) : IO UInt32 :=
  MahjongComputations.SevenTileReport.run args
