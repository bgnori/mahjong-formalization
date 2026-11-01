package mahjong_test

import (
	"testing"

	"github.com/bgnori/mahjong-formalization/mahjong"
)

func TestPublicImportableAPI(t *testing.T) {
	result, err := mahjong.ClassifyIrreducibleWait([]int{0, 4, 5, 8})
	if err != nil {
		t.Fatal(err)
	}
	if result.ClassificationID != 5 || result.PathologyProfile != mahjong.PathologyAmbiguityOnly {
		t.Fatalf("unexpected classification: %+v", result)
	}
	if len(result.Key().WaitDecompositionCodes) == 0 {
		t.Fatal("classification key has no decomposition codes")
	}
}
