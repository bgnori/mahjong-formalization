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

private def relationGroupJson
    (group : BucketClassification.WaitDecompositionRelationGroup) : Json :=
  object [
    ("waitDecompositionCodes", naturalArray group.codes),
    ("count", natural group.count),
    ("componentRelations", string group.relationDescription),
    ("representativeTiles", string (formatTiles group.representativeTiles)),
    ("representativeWaits", string (formatTiles group.representativeWaits))
  ]

private def reportJson (summary : TenTileSummary) (elapsedMs : Nat) : Json := Id.run do
  let relationRefinements := summary.irreducibleGroups.map fun group =>
    let refinedCount :=
      (summary.irreducibleRelationGroups.filter fun refined =>
        refined.codes == group.codes).length
    object [
      ("waitDecompositionCodes", naturalArray group.codes),
      ("refinedGroupCount", natural refinedCount)
    ]
  let splitGroups := summary.irreducibleGroups.filter fun group =>
    (summary.irreducibleRelationGroups.filter fun refined =>
      refined.codes == group.codes).length > 1
  let reportsInSplitGroups := splitGroups.foldl (fun count group => count + group.count) 0
  let splitRelationGroups := summary.irreducibleRelationGroups.filter fun refined =>
    (summary.irreducibleRelationGroups.filter fun other =>
      other.codes == refined.codes).length > 1
  return report 10 elapsedMs [
    ("allTileShapes", natural summary.allTenTileShapes),
    ("enumeratedDerivations", natural summary.enumeratedDerivations),
    ("tenpaiReports", natural summary.tenpaiReports),
    ("reducibility", object [
      ("reducible", natural summary.reducibleReports),
      ("irreducible", natural summary.irreducibleReports),
      ("withDisjointComponentRelations", natural summary.irreducibleDisjointReports)
    ]),
    ("waitCoreCache", object [
      ("hits", natural summary.waitCoreCacheHits),
      ("misses", natural summary.waitCoreCacheMisses),
      ("entries", natural summary.waitCoreCacheEntries)
    ]),
    ("irreducibleRelationGroupCount", natural summary.irreducibleRelationGroups.length),
    ("waitDecompositionCodesWithMultipleRelationGroups", natural splitGroups.length),
    ("irreducibleReportsInThoseCodeGroups", natural reportsInSplitGroups)
  ] [
    ("irreducibleGroupsByWaitDecompositionCodes",
      array (summary.irreducibleGroups.map codeGroup)),
    ("relationRefinements", array relationRefinements),
    ("componentRelationGroups", array (summary.irreducibleRelationGroups.map relationGroupJson)),
    ("representativeHandsInSplitGroups", array (splitRelationGroups.map relationGroupJson)),
    ("waitTileCountDistribution",
      waitTileCountDistribution summary.waitTileCountDistribution)
  ]

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
