import Mahjong.WaitDecompositionCode

namespace MahjongTests.WaitDecompositionCode

open _root_.WaitDecompositionCode
open _root_.WaitCompletionFinder

private def testHand2345678 : List Tile := manzu [1, 2, 3, 4, 5, 6, 7]
private def testHand1234 : List Tile := manzu [0, 1, 2, 3]
private def testHand1223 : List Tile := manzu [0, 1, 1, 2]
private def testHand1233 : List Tile := manzu [0, 1, 2, 2]
private def testHand1167888 : List Tile := manzu [0, 0, 5, 6, 7, 7, 7]
private def testHand1166678 : List Tile := manzu [0, 0, 5, 5, 5, 6, 7]
private def testHandT018 : List Tile := manzu [1, 1, 1, 3, 3, 4, 5]
private def testHandT026 : List Tile := manzu [1, 1, 1, 1, 2, 3, 3]
private def testHand1188 : List Tile := manzu [0, 0, 7, 7]
private def testHand1199 : List Tile := manzu [0, 0, 8, 8]

private def nineGatesComponents : List WaitComponent :=
  [{ kind := .toitsu, tiles := manzu [0, 0] },
   { kind := .shuntsu, tiles := manzu [0, 1, 2] },
   { kind := .shuntsu, tiles := manzu [3, 4, 5] },
   { kind := .shuntsu, tiles := manzu [6, 7, 8] },
   { kind := .toitsu, tiles := manzu [8, 8] }]

private def isIrreducibleTenpai (tiles : List Tile) : Bool :=
  !(canReduceMentsuPreservingWaitCores tiles)

example :
  componentRelations nineGatesComponents =
    [{ firstKind := .toitsu, secondKind := .toitsu,
       tileRelation := .disjoint },
     { firstKind := .toitsu, secondKind := .shuntsu,
       tileRelation := .overlapping },
     { firstKind := .toitsu, secondKind := .shuntsu,
       tileRelation := .overlapping },
     { firstKind := .toitsu, secondKind := .shuntsu,
       tileRelation := .disjoint },
     { firstKind := .toitsu, secondKind := .shuntsu,
       tileRelation := .disjoint },
     { firstKind := .toitsu, secondKind := .shuntsu,
       tileRelation := .disjoint },
     { firstKind := .toitsu, secondKind := .shuntsu,
       tileRelation := .disjoint },
     { firstKind := .shuntsu, secondKind := .shuntsu,
       tileRelation := .disjoint },
     { firstKind := .shuntsu, secondKind := .shuntsu,
       tileRelation := .disjoint },
     { firstKind := .shuntsu, secondKind := .shuntsu,
       tileRelation := .disjoint }] ∧
  componentRelation
    { kind := .toitsu, tiles := manzu [0, 0] }
    { kind := .shuntsu, tiles := Tile.numberedTiles .Pinzu [0, 1, 2] } =
    { firstKind := .toitsu, secondKind := .shuntsu,
      tileRelation := .disjoint } ∧
  componentRelation
    { kind := .toitsu, tiles := manzu [0, 0] }
    { kind := .toitsu, tiles := [.honor .East, .honor .East] } =
    { firstKind := .toitsu, secondKind := .toitsu,
      tileRelation := .disjoint } := by
  native_decide

example :
  waitCoreExtractions (findWaitCompletions testHand1234) =
      [{ wait := .numbered .Manzu 0,
         core := [{ kind := .tanki, tiles := [.numbered .Manzu 0] }],
         removedMentsu := [{ kind := .shuntsu, tiles := manzu [1, 2, 3] }] },
       { wait := .numbered .Manzu 3,
         core := [{ kind := .tanki, tiles := [.numbered .Manzu 3] }],
         removedMentsu := [{ kind := .shuntsu, tiles := manzu [0, 1, 2] }] }] := by
  native_decide

example :
    findWaitCores (manzu [0, 0, 0, 3]) = findWaitCores (manzu [3]) ∧
    canReduceMentsuPreservingWaitCores (manzu [0, 0, 0, 3]) = true ∧
    findWaitCores testHand1234 != findWaitCores (manzu [0]) ∧
    findWaitCores testHand1234 != findWaitCores (manzu [3]) ∧
    canReduceMentsuPreservingWaitCores testHand1234 = false := by
  native_decide

example :
  (findWaitCores testHand1223).length = 2 ∧
    findWaitDecompositionCodes testHand1223 = [21, 26] ∧
    canReduceMentsuPreservingWaitCores testHand1223 = false ∧
    determineReducibility testHand1223 = some .irreducible ∧
    (findWaitCores testHand1233).length = 2 ∧
    findWaitDecompositionCodes testHand1233 = [26, 33] ∧
    canReduceMentsuPreservingWaitCores testHand1233 = false ∧
    determineReducibility testHand1233 = some .irreducible := by
  native_decide

example :
  waitKindDecompositions (findWaitCompletions testHand2345678) =
      [{ wait := .numbered .Manzu 1, components := [.tanki, .shuntsu, .shuntsu] },
       { wait := .numbered .Manzu 4, components := [.tanki, .shuntsu, .shuntsu] },
       { wait := .numbered .Manzu 7, components := [.tanki, .shuntsu, .shuntsu] }] ∧
    waitDecompositionCodeEntries (findWaitCompletions testHand2345678) =
      [{ wait := .numbered .Manzu 1, code := 338 },
       { wait := .numbered .Manzu 4, code := 338 },
       { wait := .numbered .Manzu 7, code := 338 }] ∧
    findWaitDecompositionCodes testHand2345678 = [338, 338, 338] ∧
    findWaitDecompositionCodes testHand1167888 = [117, 117, 255, 255] ∧
    findWaitDecompositionCodes testHand1166678 = [117, 117, 255, 255] ∧
    findWaitDecompositionCodes testHand1167888 =
      findWaitDecompositionCodes testHand1166678 ∧
    findWaitDecompositionRelationClassification testHand1167888 =
      findWaitDecompositionRelationClassification testHand1166678 ∧
    findWaitDecompositionRelationClassification testHand1188 =
      findWaitDecompositionRelationClassification testHand1199 ∧
    findWaitDecompositionCodes testHandT018 = [255, 255, 273, 442] ∧
    findWaitDecompositionCodes testHandT018 = findWaitDecompositionCodes testHandT026 ∧
    findWaitDecompositionRelationClassification testHandT018 !=
      findWaitDecompositionRelationClassification testHandT026 ∧
    irreducibleSingleSuitSevenTileExamples.length = 53 ∧
    irreducibleSingleSuitSevenTileExamples.all
      (fun entry => isIrreducibleTenpai entry.2) = true ∧
    irreducibleSevenTileWaitDecompositionCodeClasses.length = 29 ∧
    irreducibleSevenTileWaitDecompositionCodeClasses.find? (fun entry =>
      entry.1 == [117, 117, 255, 255]) = some
        ([117, 117, 255, 255],
         ["1178999m", "1167888m", "1166678m", "1156777m", "1155567m",
          "1145666m", "1144456m", "1134555m", "1133345m", "1122234m",
          "1112399m", "1112388m", "1112377m", "1112366m", "1112355m"]) := by
  native_decide

end MahjongTests.WaitDecompositionCode
