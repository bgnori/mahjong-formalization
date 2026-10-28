import MahjongComputations.ExternalWaitCompletion

namespace MahjongTests.ExternalWaitCompletion

open MahjongComputations

private def ensure (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def bytesOf (values : List Nat) : ByteArray :=
  values.foldl (fun bytes value => bytes.push (UInt8.ofNat value)) ByteArray.empty

private def record3 : ExternalWaitCompletion.Record :=
  { tiles := Tile.all.take 10
    completion := {
      wait := .numbered .Pinzu 1
      winningComponents := CanonicalWinningComponents.ofList [
        WinningComponent.pair (.numbered .Manzu 0),
        WinningComponent.shuntsu .Manzu ⟨0, by decide⟩,
        WinningComponent.shuntsu .Manzu ⟨1, by decide⟩,
        WinningComponent.shuntsu .Manzu ⟨2, by decide⟩
      ]
    }
  }

private def record4 : ExternalWaitCompletion.Record :=
  { tiles := Tile.all.take 13
    completion := {
      wait := .numbered .Pinzu 4
      winningComponents := CanonicalWinningComponents.ofList [
        WinningComponent.pair (.numbered .Manzu 0),
        WinningComponent.shuntsu .Manzu ⟨0, by decide⟩,
        WinningComponent.shuntsu .Manzu ⟨1, by decide⟩,
        WinningComponent.shuntsu .Manzu ⟨2, by decide⟩,
        WinningComponent.shuntsu .Manzu ⟨3, by decide⟩
      ]
    }
  }

private def expected3 : ByteArray :=
  bytesOf ([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0, 34, 35, 36])

private def expected4 : ByteArray :=
  bytesOf ([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0, 34, 35, 36, 37])

private def byteValues (bytes : ByteArray) : List Nat :=
  bytes.data.toList.map UInt8.toNat

private def testStableRecordFormats : IO Unit := do
  ensure (ExternalWaitCompletion.encode 3 record3 == some expected3)
    "three-mentsu record encoding changed"
  ensure (ExternalWaitCompletion.decode 3 expected3 == some record3)
    "three-mentsu compatibility record failed to decode"
  ensure (ExternalWaitCompletion.encode 4 record4 == some expected4)
    "four-mentsu record encoding changed"
  ensure (ExternalWaitCompletion.decode 4 expected4 == some record4)
    "four-mentsu compatibility record failed to decode"

private def testCorruptRecordsRejected : IO Unit := do
  ensure (ExternalWaitCompletion.decode 3 (bytesOf (byteValues expected3).dropLast)).isNone
    "codec accepted a truncated record"
  ensure (ExternalWaitCompletion.decode 3 (expected3.push 0)).isNone
    "codec accepted an oversized record"
  let invalidTile := bytesOf (255 :: (byteValues expected3).drop 1)
  ensure (ExternalWaitCompletion.decode 3 invalidTile).isNone
    "codec accepted an out-of-range tile index"
  let invalidWait := bytesOf
    ((byteValues expected3).take 10 ++ [255] ++ (byteValues expected3).drop 11)
  ensure (ExternalWaitCompletion.decode 3 invalidWait).isNone
    "codec accepted an out-of-range wait index"
  let invalidComponent := bytesOf
    ((byteValues expected3).take 11 ++ [255] ++ (byteValues expected3).drop 12)
  ensure (ExternalWaitCompletion.decode 3 invalidComponent).isNone
    "codec accepted an out-of-range winning-component index"

private def writeBytes (path : System.FilePath) (bytes : ByteArray) : IO Unit :=
  IO.FS.withFile path .write fun handle => handle.write bytes

private def fileIsRejected (path : System.FilePath) : IO Bool := do
  try
    discard <| ExternalWaitCompletion.foldFile path 3 () fun _ _ => pure ()
    pure false
  catch _ =>
    pure true

private def testStableBucketHeaderAndCorruption : IO Unit := do
  let path : System.FilePath := ".lake/build/external-wait-completion-format-test.bin"
  let expectedHeader := bytesOf [77, 74, 87, 67, 1, 3, 15, 0]
  let expectedHeader4 := bytesOf [77, 74, 87, 67, 1, 4, 19, 0]
  try
    ExternalWaitCompletion.withWriter path 3 64 fun writer =>
      writer.append record3
    let header ← IO.FS.withFile path .read fun handle =>
      handle.read (USize.ofNat expectedHeader.size)
    ensure (header == expectedHeader) "external bucket header format changed"
    let decoded ← ExternalWaitCompletion.foldFile path 3 [] fun records record =>
      pure (record :: records)
    ensure (decoded == [record3]) "stable bucket fixture failed to read"

    ExternalWaitCompletion.withWriter path 4 64 fun writer =>
      writer.append record4
    let header4 ← IO.FS.withFile path .read fun handle =>
      handle.read (USize.ofNat expectedHeader4.size)
    ensure (header4 == expectedHeader4) "four-mentsu bucket header format changed"
    let decoded4 ← ExternalWaitCompletion.foldFile path 4 [] fun records record =>
      pure (record :: records)
    ensure (decoded4 == [record4]) "four-mentsu stable bucket fixture failed to read"

    writeBytes path (bytesOf ([77, 74, 87, 67, 1, 4, 19, 0] ++ byteValues expected3))
    ensure (← fileIsRejected path) "reader accepted a bucket for a different mentsu count"

    writeBytes path (bytesOf ([0, 74, 87, 67, 1, 3, 15, 0] ++ byteValues expected3))
    ensure (← fileIsRejected path) "reader accepted a bucket with a corrupt magic header"

    writeBytes path (bytesOf ([77, 74, 87, 67, 2, 3, 15, 0] ++ byteValues expected3))
    ensure (← fileIsRejected path) "reader accepted an unsupported bucket format version"

    writeBytes path (bytesOf ([77, 74, 87, 67, 1, 3, 15] ++ byteValues expected3))
    ensure (← fileIsRejected path) "reader accepted a truncated bucket header"

    writeBytes path (bytesOf (byteValues expectedHeader ++ (byteValues expected3).dropLast))
    ensure (← fileIsRejected path) "reader accepted a truncated final record"

    let invalidComponent :=
      (byteValues expected3).take 11 ++ [255] ++ (byteValues expected3).drop 12
    writeBytes path (bytesOf (byteValues expectedHeader ++ invalidComponent))
    ensure (← fileIsRejected path) "reader accepted an out-of-range record index"
  finally
    IO.FS.removeFile path

def run : IO UInt32 := do
  testStableRecordFormats
  testCorruptRecordsRejected
  testStableBucketHeaderAndCorruption
  IO.println "external wait-completion format tests passed"
  return 0

end MahjongTests.ExternalWaitCompletion

def main : IO UInt32 :=
  MahjongTests.ExternalWaitCompletion.run
