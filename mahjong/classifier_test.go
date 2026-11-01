package mahjong

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

var mpszPattern = regexp.MustCompile(`([0-9]+)([mpsz])`)

func testTenhouIDs(t *testing.T, notation string) []int {
	t.Helper()
	baseBySuit := map[byte]int{'m': 0, 'p': 9, 's': 18, 'z': 27}
	copies := make(map[int]int)
	var tileIDs []int
	for _, match := range mpszPattern.FindAllStringSubmatch(notation, -1) {
		base := baseBySuit[match[2][0]]
		for _, digit := range match[1] {
			rank := int(digit - '0')
			if rank == 0 {
				rank = 5
			}
			tileType := base + rank - 1
			copyNumber := copies[tileType]
			if copyNumber >= 4 {
				t.Fatalf("too many copies in %q", notation)
			}
			tileIDs = append(tileIDs, tileType*4+copyNumber)
			copies[tileType]++
		}
	}
	return tileIDs
}

func TestAllReportClassificationsKeepFixedIDs(t *testing.T) {
	reports := []struct {
		tileCount int
		file      string
		wantCount int
	}{
		{4, "four-tile-direct-report.json", 11},
		{7, "seven-tile-report.json", 49},
		{10, "ten-tile-report.json", 199},
		{13, "thirteen-tile-report.json", 708},
	}
	seenIDs := make(map[int]struct{})
	for _, report := range reports {
		t.Run(filepath.Base(report.file), func(t *testing.T) {
			path := filepath.Join("..", "reports", report.file)
			data, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			var decoded struct {
				Groups []struct {
					Codes          []int  `json:"waitDecompositionCodes"`
					Representative string `json:"representativeTiles"`
				} `json:"irreducibleGroupsByWaitDecompositionCodes"`
			}
			if err := json.Unmarshal(data, &decoded); err != nil {
				t.Fatal(err)
			}
			if len(decoded.Groups) != report.wantCount {
				t.Fatalf("got %d groups, want %d", len(decoded.Groups), report.wantCount)
			}
			for _, group := range decoded.Groups {
				tileIDs := testTenhouIDs(t, group.Representative)
				codes, err := WaitDecompositionCodes(tileIDs)
				if err != nil {
					t.Fatalf("%s: %v", group.Representative, err)
				}
				if !equalIntSlices(codes, group.Codes) {
					t.Errorf("%s: got codes %v, want %v", group.Representative, codes, group.Codes)
				}
				classification, err := ClassifyIrreducibleWait(tileIDs)
				if err != nil {
					t.Fatalf("%s: %v", group.Representative, err)
				}
				expectedID, ok := lookupClassification(report.tileCount, group.Codes)
				if !ok {
					t.Fatalf("report classification %v is missing from fixed table", group.Codes)
				}
				if classification.ClassificationID != expectedID {
					t.Errorf("%s: got ID %d, want %d", group.Representative, classification.ClassificationID, expectedID)
				}
				id, err := ClassifyIrreducibleWaitID(tileIDs)
				if err != nil {
					t.Fatalf("%s: %v", group.Representative, err)
				}
				if id != expectedID {
					t.Errorf("%s: ID-only API returned %d, want %d", group.Representative, id, expectedID)
				}
				seenIDs[expectedID] = struct{}{}
			}
		})
	}
	if len(seenIDs) != 967 {
		t.Fatalf("saw %d classification IDs, want 967", len(seenIDs))
	}
}

func TestWaitCorePreservingMeldsReduceRecursively(t *testing.T) {
	for _, hand := range []string{"1223m", "1223m111z", "1223m111222z", "1223m111222333z"} {
		got, err := ClassifyIrreducibleWait(testTenhouIDs(t, hand))
		if err != nil {
			t.Fatalf("%s: %v", hand, err)
		}
		if got.ClassificationID != 5 {
			t.Errorf("%s: got ID %d, want 5", hand, got.ClassificationID)
		}
	}
}

func TestReducibleTankiUsesBaseClass(t *testing.T) {
	got, err := ClassifyIrreducibleWait(testTenhouIDs(t, "1114m"))
	if err != nil {
		t.Fatal(err)
	}
	if got.ClassificationID != 967 || got.PathologyProfile != PathologyHealthy {
		t.Errorf("got ID/profile %d/%s, want 967/healthy", got.ClassificationID, got.PathologyProfile)
	}
}

func TestRedFiveIdentityIsIgnored(t *testing.T) {
	ordinary := []int{48, 53, 54, 56}
	red := []int{48, 52, 54, 56}
	ordinaryResult, err := ClassifyIrreducibleWait(ordinary)
	if err != nil {
		t.Fatal(err)
	}
	redResult, err := ClassifyIrreducibleWait(red)
	if err != nil {
		t.Fatal(err)
	}
	if ordinaryResult.ClassificationID != redResult.ClassificationID ||
		ordinaryResult.PathologyProfile != redResult.PathologyProfile {
		t.Errorf("ordinary and red fives classified differently: %+v / %+v", ordinaryResult, redResult)
	}
}

func TestPathologyProfiles(t *testing.T) {
	for _, test := range []struct {
		hand string
		want PathologyProfile
	}{
		{"1111222234444m", PathologyBoth},
		{"89p11123456777s", PathologyAmbiguityOnly},
	} {
		got, err := PathologyProfileForHand(testTenhouIDs(t, test.hand))
		if err != nil {
			t.Fatalf("%s: %v", test.hand, err)
		}
		if got != test.want {
			t.Errorf("%s: got %s, want %s", test.hand, got, test.want)
		}
	}
}

func TestPathologyRefinesEqualDecompositionCodes(t *testing.T) {
	healthy, err := ClassifyIrreducibleWait(testTenhouIDs(t, "2333345777p"))
	if err != nil {
		t.Fatal(err)
	}
	ambiguous, err := ClassifyIrreducibleWait(testTenhouIDs(t, "3335666678s"))
	if err != nil {
		t.Fatal(err)
	}
	if !equalIntSlices(healthy.WaitDecompositionCodes, ambiguous.WaitDecompositionCodes) {
		t.Fatalf("expected same decomposition codes, got %v and %v", healthy.WaitDecompositionCodes, ambiguous.WaitDecompositionCodes)
	}
	if healthy.ClassificationID != ambiguous.ClassificationID {
		t.Errorf("expected same legacy ID, got %d and %d", healthy.ClassificationID, ambiguous.ClassificationID)
	}
	if healthy.PathologyProfile != PathologyHealthy || ambiguous.PathologyProfile != PathologyAmbiguityOnly {
		t.Errorf("unexpected profiles: %s and %s", healthy.PathologyProfile, ambiguous.PathologyProfile)
	}
	if healthy.Key().PathologyProfile == ambiguous.Key().PathologyProfile {
		t.Error("pathology-aware keys should differ")
	}
}

func TestInvalidAndNonTenpaiInputs(t *testing.T) {
	for _, hand := range [][]int{{0, 0, 4, 8}, {0, 4, 8, 136}, {0}} {
		if _, err := ClassifyIrreducibleWait(hand); !errors.Is(err, ErrInvalidHand) {
			t.Errorf("%v: got error %v, want ErrInvalidHand", hand, err)
		}
	}
	if _, err := ClassifyIrreducibleWait([]int{0, 1, 2, 3}); !errors.Is(err, ErrNotTenpai) {
		t.Errorf("got error %v, want ErrNotTenpai", err)
	}
}

func equalIntSlices(first, second []int) bool {
	if len(first) != len(second) {
		return false
	}
	for index := range first {
		if first[index] != second[index] {
			return false
		}
	}
	return true
}
