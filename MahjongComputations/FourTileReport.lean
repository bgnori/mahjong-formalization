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

private def reducibilityCount (reports : List FourTileShapeReport)
    (reducibility : WaitReducibility) : Nat :=
  (reports.filter fun report => report.reducibility == some reducibility).length

private def reportsByReducibility (reports : List FourTileShapeReport)
    (reducibility : WaitReducibility) : List FourTileShapeReport :=
  reports.filter fun report => report.reducibility == some reducibility

private def reportJson
    (directReports : List FourTileShapeReport) (cache : SharedWaitCoreCacheStats)
    (elapsedMs : Nat) : Json := Id.run do
  let irreducibleReports := reportsByReducibility directReports .irreducible
  let irreducibleGroups := groupByWaitDecompositionCodes
    (·.waitDecompositionCodes) (·.tiles) (·.waits) irreducibleReports
  let irreducibleRelationGroupCount :=
    (irreducibleReports.map (·.relationClassification)).eraseDups.length
  let relationRefinements := irreducibleGroups.map fun group =>
    let refinedCount :=
      (irreducibleReports
        |>.filter (fun report => report.waitDecompositionCodes == group.codes)
        |>.map (·.relationClassification)
        |>.eraseDups).length
    object [
      ("waitDecompositionCodes", naturalArray group.codes),
      ("refinedGroupCount", natural refinedCount)
    ]
  let waitTileCounts := countOccurrences (directReports.map (·.waits.length))
  let shapeReports := directReports.map fun shape =>
    object [
      ("tiles", string (formatTiles shape.tiles)),
      ("waits", string (formatTiles shape.waits)),
      ("reducibility", match shape.reducibility with
        | none => Json.null
        | some .reducible => string "reducible"
        | some .irreducible => string "irreducible"),
      ("waitDecompositionCodes", naturalArray shape.waitDecompositionCodes),
      ("waitDecompositionCodesKey",
        string (toString (waitDecompositionCodesKey shape.waitDecompositionCodes)))
    ]
  return report 4 elapsedMs [
    ("allTileShapes", natural allFourTileShapes.length),
    ("enumeratedDerivations", natural directDerivationCount),
    ("tenpaiReports", natural directReports.length),
    ("reducibility", object [
      ("reducible", natural (reducibilityCount directReports .reducible)),
      ("irreducible", natural (reducibilityCount directReports .irreducible))
    ]),
    ("irreducibleRelationGroupCount", natural irreducibleRelationGroupCount),
    ("waitCoreCache", object [
      ("hits", natural cache.hits),
      ("misses", natural cache.misses),
      ("entries", natural cache.entries)
    ])
  ] [
    ("irreducibleGroupsByWaitDecompositionCodes",
      array (irreducibleGroups.map codeGroup)),
    ("relationRefinements", array relationRefinements),
    ("waitTileCountDistribution", waitTileCountDistribution waitTileCounts),
    ("tenpaiShapes", array shapeReports)
  ]

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
