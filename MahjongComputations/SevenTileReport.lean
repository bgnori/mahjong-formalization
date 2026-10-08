import MahjongComputations.SevenTile
import MahjongComputations.Parallel

/-!
# Seven-tile report generator

Run through Lake with `lake build sevenTileReport`.
-/

namespace MahjongComputations.SevenTileReport

open MahjongComputations.SevenTile

private def newline : String := "\n"

private def reportBody (summary : SevenTileSummary) : String :=
  let relationRefinementLines := summary.irreducibleGroups.map fun group =>
    let refinedCount :=
      (summary.irreducibleRelationClassifications.filter fun classification =>
        classification.codes == group.codes).length
    String.intercalate "\t" [toString group.codes, toString refinedCount]
  String.intercalate newline <|
    ["# Seven-tile direct derivation wait report",
     "",
     s!"allSevenTileShapes: {summary.allSevenTileShapes}",
    s!"enumeratedDerivations: {summary.enumeratedDerivations}",
     s!"tenpaiReports: {summary.tenpaiReports}",
     "",
     "## Reducibility",
     "",
     "### Reducible",
     s!"count: {summary.reducibleReports}",
    s!"waitCoreCacheHits: {summary.waitCoreCacheHits}",
    s!"waitCoreCacheMisses: {summary.waitCoreCacheMisses}",
    s!"waitCoreCacheEntries: {summary.waitCoreCacheEntries}",
     "",
     "### Irreducible",
     s!"count: {summary.irreducibleReports}",
     "",
    "#### Groups by waitDecompositionCodes",
    s!"groupCount: {summary.irreducibleGroups.length}",
    "waitDecompositionCodes\twaitDecompositionCodesKey\tcount\trepresentativeTiles\trepresentativeWaits"] ++
    summary.irreducibleGroups.map formatWaitDecompositionCodeGroup ++
    ["",
     "#### Groups by waitDecompositionCodes and ComponentRelation",
     s!"groupCount: {summary.irreducibleRelationClassifications.length}",
     "waitDecompositionCodes\trefinedGroupCount"] ++
    relationRefinementLines ++
    ["",
     "",
     "## Wait tile count distribution"] ++
    ((List.range Tile.count).map (fun index =>
      formatWaitTileCount summary.waitTileCountDistribution (index + 1))) ++
    [""]

private def reportText (elapsedMs : Nat) (body : String) : String :=
  String.intercalate newline [
    body,
    s!"calculationElapsedMs: {elapsedMs}",
    ""
  ]

def run (args : List String) : IO UInt32 := do
  let (workers, outputPath) ←
    MahjongComputations.parseWorkerArgs args "reports/seven-tile-report.txt"
  let path : System.FilePath := outputPath
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  let started ← IO.monoMsNow
  let computedSummary ← summaryParallel workers
  let body := reportBody computedSummary
  let bodySize := body.utf8ByteSize
  if bodySize == 0 then
    throw (IO.userError "empty seven-tile report body")
  let finished ← IO.monoMsNow
  IO.FS.writeFile path (reportText (finished - started) body)
  IO.println s!"wrote {path}"
  return 0

end MahjongComputations.SevenTileReport

def main (args : List String) : IO UInt32 :=
  MahjongComputations.SevenTileReport.run args
