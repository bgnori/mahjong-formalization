import MahjongComputations.FourTile
import MahjongComputations.Parallel

/-!
# Four-tile report generator

Run through Lake with `lake build fourTileReport`.
-/

namespace MahjongComputations.FourTileReport

open MahjongComputations.FourTile
open WaitDecompositionCode

private def newline : String := "\n"

private def reducibilityName : Option WaitReducibility → String
  | none => "none"
  | some .reducible => "reducible"
  | some .irreducible => "irreducible"

private def reportLine (report : FourTileShapeReport) : String :=
  String.intercalate "\t" [
    formatTiles report.tiles,
    formatTiles report.waits,
    reducibilityName report.reducibility,
    toString report.waitDecompositionCodes,
    toString (waitDecompositionCodesKey report.waitDecompositionCodes)
  ]

private def reducibilityCount (reports : List FourTileShapeReport)
    (reducibility : WaitReducibility) : Nat :=
  (reports.filter fun report => report.reducibility == some reducibility).length

private def reportsByReducibility (reports : List FourTileShapeReport)
    (reducibility : WaitReducibility) : List FourTileShapeReport :=
  reports.filter fun report => report.reducibility == some reducibility

private def reportText
    (directReports : List FourTileShapeReport) (cache : SharedWaitCoreCacheStats) : String :=
  let irreducibleReports := reportsByReducibility directReports .irreducible
  let irreducibleGroups := groupByWaitDecompositionCodes
    (·.waitDecompositionCodes) (·.tiles) (·.waits) irreducibleReports
  let irreducibleRelationGroupCount :=
    (irreducibleReports.map (·.relationClassification)).eraseDups.length
  let relationRefinementLines := irreducibleGroups.map fun group =>
    let refinedCount :=
      (irreducibleReports
        |>.filter (fun report => report.waitDecompositionCodes == group.codes)
        |>.map (·.relationClassification)
        |>.eraseDups).length
    String.intercalate "\t" [toString group.codes, toString refinedCount]
  let waitTileCounts := countOccurrences (directReports.map (·.waits.length))
  String.intercalate newline <|
    ["# Four-tile direct derivation wait report",
     "",
     s!"allFourTileShapes: {allFourTileShapes.length}",
    s!"enumeratedDerivations: {directDerivationCount}",
    s!"tenpaiReports: {directReports.length}",
      "",
     "## Reducibility",
     "",
     "### Reducible",
    s!"count: {reducibilityCount directReports .reducible}",
    s!"waitCoreCacheHits: {cache.hits}",
    s!"waitCoreCacheMisses: {cache.misses}",
    s!"waitCoreCacheEntries: {cache.entries}",
     "",
     "### Irreducible",
    s!"count: {reducibilityCount directReports .irreducible}",
     "",
    "#### Groups by waitDecompositionCodes",
    s!"groupCount: {irreducibleGroups.length}",
    "waitDecompositionCodes\twaitDecompositionCodesKey\tcount\trepresentativeTiles\trepresentativeWaits"] ++
    irreducibleGroups.map formatWaitDecompositionCodeGroup ++
    ["",
     "#### Groups by waitDecompositionCodes and ComponentRelation",
     s!"groupCount: {irreducibleRelationGroupCount}",
     "waitDecompositionCodes\trefinedGroupCount"] ++
    relationRefinementLines ++
    ["",
     "",
     "## Wait tile count distribution"] ++
    ([1, 2, 3, 4].map (formatWaitTileCount waitTileCounts)) ++
    ["",
     "## Tenpai reports",
    "tiles\twaits\treducibility\twaitDecompositionCodes\twaitDecompositionCodesKey"] ++
    directReports.map reportLine ++
    [""]

def run (args : List String) : IO UInt32 := do
  let (workers, outputPath) ←
    MahjongComputations.parseWorkerArgs args "reports/four-tile-direct-report.txt"
  let path : System.FilePath := outputPath
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  let (directReports, cache) ← directDerivationReportsParallel workers
  IO.FS.writeFile path (reportText directReports cache)
  IO.println s!"wrote {path}"
  return 0

end MahjongComputations.FourTileReport

def main (args : List String) : IO UInt32 :=
  MahjongComputations.FourTileReport.run args
