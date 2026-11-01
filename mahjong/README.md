# Go package

The Go package at `github.com/bgnori/mahjong-formalization/mahjong` classifies
standard-form tenpai hands by wait decomposition and pathology profile. Inputs
can be supplied as slices of Tenhou's 136 physical tile IDs (`0..135`) or with
the explicit Int37 APIs described below. Red fives are accepted and treated as
the corresponding ordinary five tile type by the classifier.

## Specification authority

The authoritative specification is the Lean implementation under
[`../Mahjong/`](../Mahjong/). This Go package is a subordinate port for
external consumers. It must follow the Lean definitions and generated results;
it does not define an independent specification. Make semantic changes in Lean
first and then update this package. If the two implementations disagree, Lean
takes precedence.

```go
package main

import (
	"fmt"
	"log"

	"github.com/bgnori/mahjong-formalization/mahjong"
)

func main() {
	// 1223m, with one physical ID per tile.
	hand := []int{0, 4, 5, 8}
	result, err := mahjong.ClassifyIrreducibleWait(hand)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(result.ClassificationID, result.WaitDecompositionCodes, result.PathologyProfile)
}
```

`WaitDecompositionCodes` returns the sorted decomposition codes without
reducing the hand. `PathologyProfileForHand` checks pathology marks on the
input hand itself, including reducible hands. `ClassifyIrreducibleWait` removes
complete melds that preserve the wait-core set and reports the resulting
irreducible class. Its `ClassificationID` preserves the existing code-only
global IDs; the primary classification key is the code list together with the
four-valued pathology profile.

Supported hand sizes are 4, 7, 10, and 13 tiles. Invalid physical IDs,
duplicate IDs, non-tenpai hands, and unknown or ambiguous reductions are
returned as errors. Use `errors.Is` with `ErrInvalidHand`, `ErrNotTenpai`,
`ErrUnknownClassification`, or `ErrAmbiguousReduction` to check error kinds.

## Int37 input (`aka37-int37/v1`)

Use the `Int37` suffix variants to pass one Int37 value per closed tile:

- `WaitDecompositionCodesInt37`
- `PathologyProfileForHandInt37`
- `ClassifyIrreducibleWaitInt37`
- `ClassifyIrreducibleWaitIDInt37`

Supported hand sizes are 4, 7, 10, and 13. Int37 `0`, `10`, and `20` are red
fives in manzu, pinzu, and souzu; `1..9`, `11..19`, and `21..29` encode ranks
`1..9` in those suits. Values `30..36` encode honors `1z..7z`. Repeated values
represent copies of the same kind; unlike Tenhou IDs, repeated Int37 values are
expected and do not indicate duplicate physical tiles. Each non-five kind may
occur at most four times; each red five at most once; each ordinary five at
most three times; and red plus ordinary fives per suit at most four times. Red
fives are normalized to their ordinary five kind before classification. This
format represents only closed tiles, not melds or physical copy identity.

```go
codes, err := mahjong.WaitDecompositionCodesInt37([]int{1, 2, 2, 3}) // 1223m
if err != nil {
	log.Fatal(err)
}
fmt.Println(codes)
```

The Tenhou-ID APIs and their validation behavior are unchanged. Both input
formats normalize to the same 34-kind count vector and use the same classifier.

Use the `development` dev container (or the equivalent default configuration),
which includes Go for port validation. The ten-/thirteen-tile report containers
do not include Go; their Lean computations are separate from port validation.
Run the package tests from the repository root with:

```sh
go test ./mahjong
```

The fixed classification table is generated from the checked-in Python table,
which is itself a subordinate artifact derived from the Lean computation
reports:

```sh
python3 scripts/generate_go_classification_table.py
```
