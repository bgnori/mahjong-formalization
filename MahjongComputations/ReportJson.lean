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
    ("count", natural group.count),
    ("componentRelations", string group.relationDescription),
    ("representativeTiles", string (formatTiles group.representativeTiles)),
    ("representativeWaits", string (formatTiles group.representativeWaits))
  ]

def commonSummaryFields (codeGroups : List WaitDecompositionCodeGroup)
    (relationGroups : List WaitDecompositionRelationGroup)
    (reducibleReports irreducibleReports disjointReports : Nat) :
    List (String × Json) :=
  let splitCodeGroups := codeGroups.filter fun group =>
    (relationGroups.filter fun relation => relation.codes == group.codes).length > 1
  [
    ("reducibility", object [
      ("reducible", natural reducibleReports),
      ("irreducible", natural irreducibleReports),
      ("withDisjointComponentRelations", natural disjointReports)
    ]),
    ("irreducibleRelationGroupCount", natural relationGroups.length),
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
