# Go package

The Go package at `github.com/bgnori/mahjong-formalization/mahjong` classifies
standard-form tenpai hands by wait decomposition and pathology profile. Inputs
are slices of Tenhou's 136 physical tile IDs (`0..135`); red fives are accepted
and treated as the corresponding five tile type.

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
