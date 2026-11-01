# Go package

The Go package at `github.com/bgnori/mahjong-formalization/mahjong` classifies
standard-form tenpai hands by wait decomposition and pathology profile. Inputs
are slices of Tenhou's 136 physical tile IDs (`0..135`); red fives are accepted
and treated as the corresponding five tile type.

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

The fixed classification table is generated from
`examples/irreducible_wait_classification_table.py`:

```sh
python3 scripts/generate_go_classification_table.py
```
