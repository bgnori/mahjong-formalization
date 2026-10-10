import MahjongComputations.ThirteenTile
import MahjongComputations.Parallel
import MahjongComputations.ReportJson

/-!
# Thirteen-tile report generator

Run through Lake with `lake build thirteenTileReport`.
-/

namespace MahjongComputations.ThirteenTileReport

open MahjongComputations.ThirteenTile
open MahjongComputations.ReportJson
open Lean

private structure Options where
  generationWorkers : Nat
  classificationWorkers : Nat
  bucketCount : Nat
  workDirectory : String
  outputPath : String

private def parsePositiveOption (name value : String) : IO Nat := do
  match value.toNat? with
  | some parsed =>
      if parsed == 0 then throw (IO.userError s!"{name} must be greater than zero")
      return parsed
  | none => throw (IO.userError s!"invalid value for {name}: {value}")

private def parseArgs (args : List String) : IO Options := do
  let availableWorkers ← MahjongComputations.availableWorkerCount
  let mut options : Options := {
    generationWorkers := availableWorkers
    classificationWorkers := min 8 availableWorkers
    bucketCount := 256
    workDirectory := ".lake/build/thirteen-tile-buckets"
    outputPath := "reports/thirteen-tile-report.json"
  }
  for arg in args do
    if arg.startsWith "--generation-workers=" then
      let workers ← parsePositiveOption "--generation-workers" (arg.drop 21).toString
      options := { options with generationWorkers := workers }
    else if arg.startsWith "--classification-workers=" then
      let workers ← parsePositiveOption "--classification-workers" (arg.drop 25).toString
      options := { options with classificationWorkers := workers }
    else if arg.startsWith "--workers=" then
      let workers ← parsePositiveOption "--workers" (arg.drop 10).toString
      options := { options with generationWorkers := workers, classificationWorkers := workers }
    else if arg.startsWith "--buckets=" then
      let bucketCount ← parsePositiveOption "--buckets" (arg.drop 10).toString
      options := { options with bucketCount }
    else if arg.startsWith "--work-dir=" then
      options := { options with workDirectory := (arg.drop 11).toString }
    else if arg.startsWith "workers=" then
      throw (IO.userError s!"invalid worker option: {arg}; use --{arg}")
    else if arg.startsWith "--" then
      throw (IO.userError s!"unknown option: {arg}")
    else
      options := { options with outputPath := arg }
  return options

private def reportJson (result : ThirteenTileRunResult) (elapsedMs : Nat) : Json :=
  let summary := result.summary
  report 13 elapsedMs ([
    ("allTileShapes", natural summary.allThirteenTileShapes),
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

def run (args : List String) : IO UInt32 := do
  let options ← parseArgs args
  let path : System.FilePath := options.outputPath
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  let started ← IO.monoMsNow
  let result ← summaryParallel options.generationWorkers options.classificationWorkers
    options.workDirectory options.bucketCount
  let finished ← IO.monoMsNow
  IO.FS.writeFile path (encode (reportJson result (finished - started)))
  IO.println s!"wrote {path}"
  return 0

end MahjongComputations.ThirteenTileReport

def main (args : List String) : IO UInt32 :=
  MahjongComputations.ThirteenTileReport.run args
