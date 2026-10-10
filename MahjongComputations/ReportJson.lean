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

def waitTileCountDistribution (counts : List (Nat × Nat)) : Json :=
  array <| (List.range Tile.count).map fun index =>
    let waitTileKinds := index + 1
    let reportCount :=
      (counts.find? fun entry => entry.1 == waitTileKinds).map Prod.snd |>.getD 0
    object [
      ("waitTileKinds", natural waitTileKinds),
      ("reportCount", natural reportCount)
    ]

def report (tileCount elapsedMs : Nat)
    (summaryFields dataFields : List (String × Json)) : Json :=
  object <|
    [ ("schemaVersion", natural 1)
    , ("reportType", string "mahjong-wait-report")
    , ("tileCount", natural tileCount)
    , ("calculationElapsedMs", natural elapsedMs)
    , ("summary", object summaryFields)
    ] ++ dataFields

def encode (json : Json) : String :=
  json.pretty ++ "\n"

end MahjongComputations.ReportJson
