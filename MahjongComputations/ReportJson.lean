import Lean
import MahjongComputations.Common
import Mahjong.WaitDecompositionCode

namespace MahjongComputations.ReportJson

open Lean
open WaitDecompositionCode

def object (fields : List (String × Json)) : Json :=
  Json.mkObj fields

def array (values : List Json) : Json :=
  Json.arr values.toArray

def natural (value : Nat) : Json :=
  Json.num (JsonNumber.fromNat value)

def string (value : String) : Json :=
  Json.str value

def naturalArray (values : List Nat) : Json :=
  array (values.map natural)

def pathologyName : WaitPathology → String
  | .waitSuppression => "waitSuppression"
  | .redundantAmbiguity => "redundantAmbiguity"

def pathologySummaryFields (groups : List WaitPathologyGroup) : List (String × Json) :=
  [("pathologies", object <|
    [WaitPathology.waitSuppression, .redundantAmbiguity].map fun kind =>
      (pathologyName kind, natural <|
        groups.foldl (fun count group =>
          count + if group.witness.pathology == kind then group.count else 0) 0))]

def pathologyDataFields (groups : List WaitPathologyGroup) : List (String × Json) :=
  [("pathologyGroups", array <| groups.map fun group =>
    object [
      ("pathology", string (pathologyName group.witness.pathology)),
      ("waitDecompositionCodes", naturalArray group.codes),
      ("reducibility", string (if group.reducible then "reducible" else "irreducible")),
      ("count", natural group.count),
      ("representativeTiles", string (formatTiles group.representativeTiles)),
      ("representativeWaits", string (formatTiles group.representativeWaits)),
      ("removedComponent", string <|
        formatTiles (group.representativeTiles.diff group.witness.remainingTiles)),
      ("remainingTiles", string (formatTiles group.witness.remainingTiles)),
      ("remainingWaits", string (formatTiles group.witness.remainingWaits)),
      ("originalCoreCount", natural group.witness.originalCoreCount),
      ("remainingCoreCount", natural group.witness.remainingCoreCount)
    ])]

def codeGroup (group : WaitDecompositionCodeGroup) : Json :=
  object [
    ("waitDecompositionCodes", naturalArray group.codes),
    ("waitDecompositionCodesKey", string (toString (waitDecompositionCodesKey group.codes))),
    ("count", natural group.count),
    ("representativeTiles", string (formatTiles group.representativeTiles)),
    ("representativeWaits", string (formatTiles group.representativeWaits))
  ]

def relationGroup (group : WaitDecompositionRelationGroup) : Json :=
  object [
    ("waitDecompositionCodes", naturalArray group.codes),
    ("componentRelationKey", naturalArray group.relationKey),
    ("count", natural group.count),
    ("waitSuppressionCount", natural group.waitSuppressionCount),
    ("redundantAmbiguityCount", natural group.redundantAmbiguityCount),
    ("bothPathologiesCount", natural group.bothPathologiesCount),
    ("componentRelations", string group.relationDescription),
    ("representativeTiles", string (formatTiles group.representativeTiles)),
    ("representativeWaits", string (formatTiles group.representativeWaits)),
    ("pathologyProfileRepresentatives", array <|
      group.pathologyProfileRepresentatives.map fun representative =>
        object [
          ("profile", string <|
            if representative.waitSuppression then
              if representative.redundantAmbiguity then "both" else "suppressionOnly"
            else if representative.redundantAmbiguity then "ambiguityOnly" else "healthy"),
          ("representativeTiles", string (formatTiles representative.tiles)),
          ("representativeWaits", string (formatTiles representative.waits))
        ])
  ]

def commonSummaryFields (codeGroups : List WaitDecompositionCodeGroup)
    (relationGroups : List WaitDecompositionRelationGroup)
    (reducibleReports irreducibleReports disjointReports : Nat) :
    List (String × Json) :=
  let splitCodeGroups := codeGroups.filter fun group =>
    (relationGroups.filter fun relation => relation.codes == group.codes).length > 1
  let pathologicalRelationGroups := relationGroups.filter fun group =>
    group.waitSuppressionCount > 0 || group.redundantAmbiguityCount > 0
  let mixedPathologyRelationGroups := relationGroups.filter fun group =>
    let healthyCount :=
      group.count -
        (group.waitSuppressionCount + group.redundantAmbiguityCount -
          group.bothPathologiesCount)
    let suppressionOnlyCount := group.waitSuppressionCount - group.bothPathologiesCount
    let ambiguityOnlyCount := group.redundantAmbiguityCount - group.bothPathologiesCount
    [healthyCount, suppressionOnlyCount, ambiguityOnlyCount, group.bothPathologiesCount]
      |>.filter (· > 0)
      |>.length > 1
  [
    ("reducibility", object [
      ("reducible", natural reducibleReports),
      ("irreducible", natural irreducibleReports),
      ("withDisjointComponentRelations", natural disjointReports)
    ]),
    ("irreducibleRelationGroupCount", natural relationGroups.length),
    ("pathologicalRelationGroupCount", natural pathologicalRelationGroups.length),
    ("mixedPathologyDegreeRelationGroupCount", natural mixedPathologyRelationGroups.length),
    ("waitDecompositionCodesWithMultipleRelationGroups", natural splitCodeGroups.length),
    ("irreducibleReportsInThoseCodeGroups",
      natural (splitCodeGroups.foldl (fun count group => count + group.count) 0))
  ]

def waitTileCountDistribution (counts : List (Nat × Nat)) : Json :=
  array <| (List.range Tile.count).map fun index =>
    let waitTileKinds := index + 1
    let reportCount :=
      (counts.find? fun entry => entry.1 == waitTileKinds).map Prod.snd |>.getD 0
    object [
      ("waitTileKinds", natural waitTileKinds),
      ("reportCount", natural reportCount)
    ]

def commonDataFields (codeGroups : List WaitDecompositionCodeGroup)
    (relationGroups : List WaitDecompositionRelationGroup)
    (distribution : List (Nat × Nat)) : List (String × Json) :=
  let relationRefinements := codeGroups.map fun group =>
    let refinedCount :=
      (relationGroups.filter fun relation => relation.codes == group.codes).length
    object [
      ("waitDecompositionCodes", naturalArray group.codes),
      ("refinedGroupCount", natural refinedCount)
    ]
  let splitRelationGroups := relationGroups.filter fun group =>
    (relationGroups.filter fun other => other.codes == group.codes).length > 1
  [
    ("irreducibleGroupsByWaitDecompositionCodes",
      array (codeGroups.map codeGroup)),
    ("relationRefinements", array relationRefinements),
    ("componentRelationGroups", array (relationGroups.map relationGroup)),
    ("representativeHandsInSplitGroups",
      array (splitRelationGroups.map relationGroup)),
    ("waitTileCountDistribution", waitTileCountDistribution distribution)
  ]

def report (tileCount elapsedMs : Nat)
    (summaryFields dataFields : List (String × Json)) : Json :=
  object <|
    [ ("schemaVersion", natural 2)
    , ("reportType", string "mahjong-wait-report")
    , ("tileCount", natural tileCount)
    , ("calculationElapsedMs", natural elapsedMs)
    , ("summary", object summaryFields)
    ] ++ dataFields

def encode (json : Json) : String :=
  json.pretty ++ "\n"

end MahjongComputations.ReportJson
