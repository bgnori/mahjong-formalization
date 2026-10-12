import Mahjong.WaitDecompositionCode
import MahjongComputations.Common

namespace MahjongTests.WaitDecompositionCode

open _root_.WaitDecompositionCode
open _root_.WaitCompletionFinder
open _root_.MahjongComputations

private structure ClassificationPathologyObservation where
  codes : List Nat
  relationKey : List Nat
  pathologyDegree : Nat

private structure ClassificationPathologyState where
  observations : List ClassificationPathologyObservation
  waitCoreCache : WaitCoreCache
  uniform : Bool

private def pathologyDegree (witnesses : List WaitPathologyWitness) : Nat :=
  (if witnesses.any (fun witness => witness.pathology == .waitSuppression) then 1 else 0) +
    (if witnesses.any (fun witness => witness.pathology == .redundantAmbiguity) then 2 else 0)

private def addClassificationPathologyObservation (irreducibleOnly : Bool)
    (state : ClassificationPathologyState) (group : WaitCompletionGroup) :
    ClassificationPathologyState :=
  if !state.uniform then state else
  let (reducible, waitCoreCache) :=
    canReduceMentsuPreservingWaitCoresCached
      group.tiles group.completions state.waitCoreCache
  if irreducibleOnly && reducible then { state with waitCoreCache } else
  let (witnesses, waitCoreCache) :=
    waitPathologyWitnessesCached group.tiles group.completions waitCoreCache
  let classification := waitDecompositionRelationClassification group.completions
  let codes := waitDecompositionCodes group.completions
  let relationKey := waitDecompositionRelationKey classification
  let degree := pathologyDegree witnesses
  match state.observations.find? fun observation =>
      observation.codes == codes && observation.relationKey == relationKey with
  | none =>
      { observations := { codes, relationKey, pathologyDegree := degree } :: state.observations
        waitCoreCache
        uniform := true }
  | some observation =>
      { state with waitCoreCache, uniform := observation.pathologyDegree == degree }

/--
Whether every standard-form tenpai hand generated for `mentsuCount` has a pathology
degree determined by its wait-decomposition codes and component-relation classification.
-/
def tenpaiRelationClassificationHasUniformPathologyDegree
    (mentsuCount : Nat) (irreducibleOnly : Bool := false) : Bool :=
  let groups := (canonicalWaitCompletionGroups mentsuCount).groups
  let result := groups.foldl (addClassificationPathologyObservation irreducibleOnly) {
    observations := []
    waitCoreCache := emptyWaitCoreCache
    uniform := true
  }
  result.uniform

/--
Among all generated four-tile standard-form tenpai hands, equal decomposition codes
and component relations imply equal pathology degree.
-/
theorem fourTileTenpai_relationClassification_determines_pathologyDegree :
    tenpaiRelationClassificationHasUniformPathologyDegree 1 = true := by
  native_decide

/--
Among generated irreducible seven-tile standard-form tenpai hands, equal
decomposition codes and component relations imply equal pathology degree.
-/
theorem sevenTileIrreducibleTenpai_relationClassification_determines_pathologyDegree :
    tenpaiRelationClassificationHasUniformPathologyDegree 2 true = true := by
  native_decide

private def healthySevenTileCounterexample : List Tile :=
  manzu [2, 3, 4, 4, 4, 4] ++ Tile.numberedTiles .Pinzu [5]

private def suppressedSevenTileCounterexample : List Tile :=
  manzu [2, 2, 2, 2, 3, 4, 5]

/--
Without the irreducibility restriction, seven-tile tenpai hands provide a
counterexample: the same classification can have different pathology degrees.
-/
theorem sevenTileTenpai_relationClassification_doesNotDeterminePathologyDegree :
    let healthyCompletions := findWaitCompletions healthySevenTileCounterexample
    let suppressedCompletions := findWaitCompletions suppressedSevenTileCounterexample
    !healthyCompletions.isEmpty &&
    !suppressedCompletions.isEmpty &&
    waitDecompositionCodes healthyCompletions =
      waitDecompositionCodes suppressedCompletions &&
    waitDecompositionRelationClassification healthyCompletions =
      waitDecompositionRelationClassification suppressedCompletions &&
    pathologyDegree (waitPathologyWitnesses healthySevenTileCounterexample) = 0 &&
    pathologyDegree (waitPathologyWitnesses suppressedSevenTileCounterexample) = 1 := by
  native_decide

private def firstHealthyTenTileCounterexample : List Tile :=
  Tile.numberedTiles .Pinzu [1, 2, 2, 2, 2, 3, 4, 6, 6, 6]

private def firstAmbiguousTenTileCounterexample : List Tile :=
  Tile.numberedTiles .Souzu [2, 2, 2, 4, 5, 5, 5, 5, 6, 7]

private def secondHealthyTenTileCounterexample : List Tile :=
  manzu [1, 2, 3, 4, 4, 4, 5, 6, 7, 8]

private def secondAmbiguousTenTileCounterexample : List Tile :=
  Tile.numberedTiles .Pinzu [0, 1, 2, 3, 3, 3, 4, 5, 6, 7]

private def isIrreducibleTenpaiWithDegree (tiles : List Tile) (degree : Nat) : Bool :=
  let completions := findWaitCompletions tiles
  !completions.isEmpty &&
    !canReduceMentsuPreservingWaitCores tiles &&
    pathologyDegree (waitPathologyWitnesses tiles) == degree

private def hasSameRelationClassification (first second : List Tile) : Bool :=
  let firstCompletions := findWaitCompletions first
  let secondCompletions := findWaitCompletions second
  waitDecompositionCodes firstCompletions == waitDecompositionCodes secondCompletions &&
    waitDecompositionRelationClassification firstCompletions ==
      waitDecompositionRelationClassification secondCompletions

/--
At ten tiles, even irreducible tenpai hands can share decomposition codes and
component relations while having different pathology degrees.
-/
theorem tenTileIrreducibleTenpai_relationClassification_doesNotDeterminePathologyDegree :
    isIrreducibleTenpaiWithDegree firstHealthyTenTileCounterexample 0 &&
    isIrreducibleTenpaiWithDegree firstAmbiguousTenTileCounterexample 2 &&
    hasSameRelationClassification
      firstHealthyTenTileCounterexample firstAmbiguousTenTileCounterexample &&
    isIrreducibleTenpaiWithDegree secondHealthyTenTileCounterexample 0 &&
    isIrreducibleTenpaiWithDegree secondAmbiguousTenTileCounterexample 2 &&
    hasSameRelationClassification
      secondHealthyTenTileCounterexample secondAmbiguousTenTileCounterexample := by
  native_decide

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

private def suppressionHand : List Tile :=
  manzu [0, 0, 0, 0, 1, 1, 1, 1, 2, 3, 3, 3, 3]

private def ambiguityHand : List Tile :=
  Tile.numberedTiles .Pinzu [7, 8] ++
    Tile.numberedTiles .Souzu [0, 0, 0, 1, 2, 3, 4, 5, 6, 6, 6]

example :
    waitsFromWaitCoreKeys (waitCoreKeys (findWaitCores suppressionHand)) = manzu [2] ∧
    waitsFromWaitCoreKeys (waitCoreKeys (findWaitCores (manzu [0]))) = manzu [0] ∧
    waitsFromWaitCoreKeys [] = [] := by native_decide

example :
    (waitPathologyWitnesses suppressionHand).any
      (fun w => w.pathology == .waitSuppression &&
        w.remainingWaits.length > 1) = true ∧
    (waitPathologyWitnesses suppressionHand).any
      (fun w => w.pathology == .redundantAmbiguity) = true ∧
    (waitPathologyWitnesses ambiguityHand).length = 1 ∧
    (waitPathologyWitnesses ambiguityHand).all
      (fun w => w.pathology == .redundantAmbiguity &&
        w.remainingWaits == Tile.numberedTiles .Pinzu [6] &&
        w.originalCoreCount == 2 && w.remainingCoreCount == 1) = true ∧
    waitPathologyWitnesses (manzu [0, 0, 0, 3]) = [] ∧
    waitPathologyWitnesses testHand1234 = [] ∧
    waitPathologyWitnesses (manzu [0]) = [] ∧
    waitPathologyWitnesses [] = [] := by native_decide

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
