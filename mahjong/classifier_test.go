package mahjong

import (
	"encoding/json"
	"errors"
	"math/rand"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
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

func testInt37OfTileID(tileID int) int {
	kind := tileID / 4
	copyNumber := tileID % 4
	if kind >= 27 {
		return 30 + kind - 27
	}
	suit := kind / 9
	rank := kind%9 + 1
	offset := suit * 10
	if rank == 5 && copyNumber == 0 {
		return offset
	}
	return offset + rank
}

func testKindFromInt37(tile int) int {
	switch {
	case tile == 0:
		return 4
	case tile >= 1 && tile <= 9:
		return tile - 1
	case tile == 10:
		return 13
	case tile >= 11 && tile <= 19:
		return tile - 2
	case tile == 20:
		return 22
	case tile >= 21 && tile <= 29:
		return tile - 3
	default:
		return tile - 3
	}
}

func TestInt37MappingCoversEveryTenhouPhysicalID(t *testing.T) {
	for kind := 0; kind < 34; kind++ {
		var projectedKind int
		for copyNumber := 0; copyNumber < 4; copyNumber++ {
			tileID := kind*4 + copyNumber
			int37 := testInt37OfTileID(tileID)
			projectedKind = testKindFromInt37(int37)
			if projectedKind != kind {
				t.Errorf("physical tile ID %d maps to kind %d, want id/4 kind %d", tileID, projectedKind, kind)
			}

			hand := []int{int37}
			for filler := 0; len(hand) < 4; filler++ {
				if testKindFromInt37(filler) != projectedKind {
					hand = append(hand, filler)
				}
			}
			counts, err := countsFromInt37(hand)
			if err != nil {
				t.Fatalf("physical tile ID %d -> Int37 %d: %v", tileID, int37, err)
			}
			if counts[kind] != 1 {
				t.Errorf("physical tile ID %d -> Int37 %d projected to counts %v", tileID, int37, counts)
			}
		}
	}

	for tileID, want := range map[int]int{16: 0, 52: 10, 88: 20, 17: 5, 53: 15, 89: 25} {
		if got := testInt37OfTileID(tileID); got != want {
			t.Errorf("physical tile ID %d maps to Int37 %d, want %d", tileID, got, want)
		}
	}
}

func TestInt37Validation(t *testing.T) {
	validAtCapacity := []int{1, 1, 1, 1, 2, 3, 4}
	if _, err := countsFromInt37(validAtCapacity); err != nil {
		t.Fatalf("four copies of a non-five kind should be accepted: %v", err)
	}
	validFives := []int{0, 5, 5, 5}
	if _, err := countsFromInt37(validFives); err != nil {
		t.Fatalf("one red and three ordinary fives should be accepted: %v", err)
	}

	for _, hand := range [][]int{
		{1, 2, 3},
		{1, 2, 3, 4, 5},
		{-1, 1, 2, 3},
		{37, 1, 2, 3},
		{0, 0, 1, 2},
		{5, 5, 5, 5},
		{1, 1, 1, 1, 1, 2, 3},
		{0, 5, 5, 5, 5, 1, 2},
	} {
		if _, err := countsFromInt37(hand); !errors.Is(err, ErrInvalidHand) {
			t.Errorf("%v: got error %v, want ErrInvalidHand", hand, err)
		}
	}

	invalid := []int{0, 0, 1, 2}
	publicAPIs := []struct {
		name string
		call func() error
	}{
		{"WaitDecompositionCodesInt37", func() error { _, err := WaitDecompositionCodesInt37(invalid); return err }},
		{"PathologyProfileForHandInt37", func() error { _, err := PathologyProfileForHandInt37(invalid); return err }},
		{"ClassifyIrreducibleWaitInt37", func() error { _, err := ClassifyIrreducibleWaitInt37(invalid); return err }},
		{"ClassifyIrreducibleWaitIDInt37", func() error { _, err := ClassifyIrreducibleWaitIDInt37(invalid); return err }},
	}
	for _, api := range publicAPIs {
		if err := api.call(); !errors.Is(err, ErrInvalidHand) {
			t.Errorf("%s: got error %v, want ErrInvalidHand", api.name, err)
		}
	}
}

func TestInt37APIsMatchTenhouAPIs(t *testing.T) {
	hands := []string{
		"1223m",
		"1223m111z",
		"1223m111222z",
		"1223m111222333z",
		"05m12p",
	}
	for _, notation := range hands {
		t.Run(notation, func(t *testing.T) {
			assertInt37APIsMatchTenhou(t, testTenhouIDs(t, notation))
		})
	}
}

func TestInt37APIsMatchGeneratedTenhouHands(t *testing.T) {
	random := rand.New(rand.NewSource(37))
	melds := make([][]int, 0, 55)
	for kind := 0; kind < tileTypeCount; kind++ {
		melds = append(melds, []int{kind, kind, kind})
	}
	for suit := 0; suit < 3; suit++ {
		for rank := 0; rank <= 6; rank++ {
			start := suit*9 + rank
			melds = append(melds, []int{start, start + 1, start + 2})
		}
	}

	for _, handSize := range []int{4, 7, 10, 13} {
		t.Run(strconv.Itoa(handSize), func(t *testing.T) {
			seen := make(map[[13]int]struct{})
			for generated := 0; generated < 16; {
				tileIDs := testTenhouIDs(t, "1223m")
				var counts handCounts
				var used [physicalTileCount]bool
				for index, originalTileID := range tileIDs {
					kind := originalTileID / 4
					availableCopies := make([]int, 0, 4)
					for copyNumber := 0; copyNumber < 4; copyNumber++ {
						tileID := kind*4 + copyNumber
						if !used[tileID] {
							availableCopies = append(availableCopies, tileID)
						}
					}
					tileID := availableCopies[random.Intn(len(availableCopies))]
					tileIDs[index] = tileID
					used[tileID] = true
					counts[kind]++
				}

				possible := true
				for meldIndex := 0; meldIndex < (handSize-4)/3; meldIndex++ {
					availableMelds := make([][]int, 0, len(melds))
					for _, meld := range melds {
						fits := true
						meldCounts := make(map[int]uint8)
						for _, kind := range meld {
							meldCounts[kind]++
							if counts[kind]+meldCounts[kind] > 4 {
								fits = false
								break
							}
						}
						if fits {
							availableMelds = append(availableMelds, meld)
						}
					}
					if len(availableMelds) == 0 {
						possible = false
						break
					}

					for _, kind := range availableMelds[random.Intn(len(availableMelds))] {
						availableCopies := make([]int, 0, 4)
						for copyNumber := 0; copyNumber < 4; copyNumber++ {
							tileID := kind*4 + copyNumber
							if !used[tileID] {
								availableCopies = append(availableCopies, tileID)
							}
						}
						tileID := availableCopies[random.Intn(len(availableCopies))]
						used[tileID] = true
						counts[kind]++
						tileIDs = append(tileIDs, tileID)
					}
				}
				if !possible {
					continue
				}

				sort.Ints(tileIDs)
				var key [13]int
				copy(key[:], tileIDs)
				if _, duplicate := seen[key]; duplicate {
					continue
				}
				seen[key] = struct{}{}
				generated++
				assertInt37APIsMatchTenhou(t, tileIDs)
			}
		})
	}
}

func assertInt37APIsMatchTenhou(t *testing.T, tileIDs []int) {
	t.Helper()
	int37Tiles := make([]int, len(tileIDs))
	for index, tileID := range tileIDs {
		int37Tiles[index] = testInt37OfTileID(tileID)
	}

	tenhouCodes, tenhouErr := WaitDecompositionCodes(tileIDs)
	int37Codes, int37Err := WaitDecompositionCodesInt37(int37Tiles)
	if tenhouErr != nil || int37Err != nil {
		t.Fatalf("expected tenpai hand: Tenhou error %v, Int37 error %v", tenhouErr, int37Err)
	}
	if !errors.Is(tenhouErr, int37Err) || !equalIntSlices(tenhouCodes, int37Codes) {
		t.Errorf("decomposition codes: Tenhou %v/%v, Int37 %v/%v", tenhouCodes, tenhouErr, int37Codes, int37Err)
	}

	tenhouProfile, tenhouErr := PathologyProfileForHand(tileIDs)
	int37Profile, int37Err := PathologyProfileForHandInt37(int37Tiles)
	if !errors.Is(tenhouErr, int37Err) || tenhouProfile != int37Profile {
		t.Errorf("pathology profile: Tenhou %s/%v, Int37 %s/%v", tenhouProfile, tenhouErr, int37Profile, int37Err)
	}

	tenhouClass, tenhouErr := ClassifyIrreducibleWait(tileIDs)
	int37Class, int37Err := ClassifyIrreducibleWaitInt37(int37Tiles)
	if !errors.Is(tenhouErr, int37Err) ||
		!equalIntSlices(tenhouClass.WaitDecompositionCodes, int37Class.WaitDecompositionCodes) ||
		tenhouClass.PathologyProfile != int37Class.PathologyProfile ||
		tenhouClass.ClassificationID != int37Class.ClassificationID {
		t.Errorf("classification: Tenhou %+v/%v, Int37 %+v/%v", tenhouClass, tenhouErr, int37Class, int37Err)
	}

	tenhouID, tenhouErr := ClassifyIrreducibleWaitID(tileIDs)
	int37ID, int37Err := ClassifyIrreducibleWaitIDInt37(int37Tiles)
	if !errors.Is(tenhouErr, int37Err) || tenhouID != int37ID {
		t.Errorf("classification ID: Tenhou %d/%v, Int37 %d/%v", tenhouID, tenhouErr, int37ID, int37Err)
	}
}

func TestInt37RedFiveSubstitutionPreservesClassification(t *testing.T) {
	red := []int{0, 5, 11, 12}
	ordinary := []int{5, 5, 11, 12}

	redCodes, redErr := WaitDecompositionCodesInt37(red)
	ordinaryCodes, ordinaryErr := WaitDecompositionCodesInt37(ordinary)
	if redErr != nil || ordinaryErr != nil || !equalIntSlices(redCodes, ordinaryCodes) {
		t.Fatalf("decomposition codes differ: red %v/%v, ordinary %v/%v", redCodes, redErr, ordinaryCodes, ordinaryErr)
	}

	redProfile, redErr := PathologyProfileForHandInt37(red)
	ordinaryProfile, ordinaryErr := PathologyProfileForHandInt37(ordinary)
	if redErr != nil || ordinaryErr != nil || redProfile != ordinaryProfile {
		t.Fatalf("pathology profiles differ: red %s/%v, ordinary %s/%v", redProfile, redErr, ordinaryProfile, ordinaryErr)
	}

	redClass, redErr := ClassifyIrreducibleWaitInt37(red)
	ordinaryClass, ordinaryErr := ClassifyIrreducibleWaitInt37(ordinary)
	if redErr != nil || ordinaryErr != nil ||
		!equalIntSlices(redClass.WaitDecompositionCodes, ordinaryClass.WaitDecompositionCodes) ||
		redClass.PathologyProfile != ordinaryClass.PathologyProfile ||
		redClass.ClassificationID != ordinaryClass.ClassificationID {
		t.Fatalf("classifications differ: red %+v/%v, ordinary %+v/%v", redClass, redErr, ordinaryClass, ordinaryErr)
	}

	redID, redErr := ClassifyIrreducibleWaitIDInt37(red)
	ordinaryID, ordinaryErr := ClassifyIrreducibleWaitIDInt37(ordinary)
	if redErr != nil || ordinaryErr != nil || redID != ordinaryID {
		t.Fatalf("classification IDs differ: red %d/%v, ordinary %d/%v", redID, redErr, ordinaryID, ordinaryErr)
	}
}

func TestInt37ErrorsMatchTenhouClassificationErrors(t *testing.T) {
	tileIDs := testTenhouIDs(t, "1111m")
	int37Tiles := make([]int, len(tileIDs))
	for index, tileID := range tileIDs {
		int37Tiles[index] = testInt37OfTileID(tileID)
	}
	if _, err := ClassifyIrreducibleWait(tileIDs); !errors.Is(err, ErrNotTenpai) {
		t.Fatalf("Tenhou input: got %v, want ErrNotTenpai", err)
	}
	if _, err := ClassifyIrreducibleWaitInt37(int37Tiles); !errors.Is(err, ErrNotTenpai) {
		t.Fatalf("Int37 input: got %v, want ErrNotTenpai", err)
	}
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
