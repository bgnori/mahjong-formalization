import MahjongComputations.FourTile
import MahjongComputations.Parallel
import MahjongComputations.ReportJson

/-!
# Four-tile report generator

Run through Lake with `lake build fourTileReport`.
-/

namespace MahjongComputations.FourTileReport

open MahjongComputations.FourTile
open MahjongComputations.ReportJson
open Lean
open WaitDecompositionCode

private def reportsByReducibility (reports : List FourTileShapeReport)
    (reducibility : WaitReducibility) : List FourTileShapeReport :=
  reports.filter fun report => report.reducibility == some reducibility

private def reportJson
    (directReports : List FourTileShapeReport) (cache : SharedWaitCoreCacheStats)
    (elapsedMs : Nat) : Json := Id.run do
  let irreducibleReports := reportsByReducibility directReports .irreducible
  let irreducibleGroups := groupByWaitDecompositionCodes
    (·.waitDecompositionCodes) (·.tiles) (·.waits) irreducibleReports
  let irreducibleRelationGroups := irreducibleReports.foldl (fun groups shape =>
    addWaitDecompositionRelationGroup shape.waitDecompositionCodes
      (waitDecompositionRelationKey shape.relationClassification)
      shape.tiles shape.waits
      (waitDecompositionRelationDescription shape.relationClassification) groups) []
  let disjointReports := (irreducibleReports.filter fun shape =>
    hasDisjointComponentRelation shape.relationClassification).length
  let commonSummary := commonSummaryFields irreducibleGroups irreducibleRelationGroups
    (reportsByReducibility directReports .reducible).length irreducibleReports.length disjointReports
  let commonData := commonDataFields irreducibleGroups irreducibleRelationGroups
    (countOccurrences (directReports.map (·.waits.length)))
  return report 4 elapsedMs ([
    ("allTileShapes", natural allFourTileShapes.length),
    ("enumeratedDerivations", natural directDerivationCount),
    ("tenpaiReports", natural directReports.length),
    ("waitCoreCache", object [
      ("hits", natural cache.hits),
      ("misses", natural cache.misses),
      ("entries", natural cache.entries)
    ])
  ] ++ commonSummary) (commonData)

def run (args : List String) : IO UInt32 := do
  let (workers, outputPath) ←
    MahjongComputations.parseWorkerArgs args "reports/four-tile-direct-report.json"
  let path : System.FilePath := outputPath
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  let started ← IO.monoMsNow
  let (directReports, cache) ← directDerivationReportsParallel workers
  let finished ← IO.monoMsNow
  IO.FS.writeFile path (encode (reportJson directReports cache (finished - started)))
  IO.println s!"wrote {path}"
  return 0

end MahjongComputations.FourTileReport

def main (args : List String) : IO UInt32 :=
  MahjongComputations.FourTileReport.run args
