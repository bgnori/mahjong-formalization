// Package mahjong classifies standard-form tenpai hands by wait decomposition
// and by the pathologies exposed by removing one completed meld.
package mahjong

import (
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
)

const (
	tileTypeCount     = 34
	physicalTileCount = 136
)

var (
	// ErrInvalidHand means the input is not a legal supported hand.
	ErrInvalidHand = errors.New("invalid hand")
	// ErrNotTenpai means the hand has no standard-form wait.
	ErrNotTenpai = errors.New("hand is not a standard-form tenpai hand")
	// ErrUnknownClassification means the irreducible code list is absent from
	// the fixed classification table.
	ErrUnknownClassification = errors.New("unknown irreducible classification")
	// ErrAmbiguousReduction means wait-core-preserving reductions reach
	// different irreducible classifications.
	ErrAmbiguousReduction = errors.New("ambiguous wait-core-preserving reduction")
)

// PathologyProfile describes marks found by inspecting single completed-meld
// removals. A hand may have both pathology marks.
type PathologyProfile string

const (
	PathologyHealthy         PathologyProfile = "healthy"
	PathologySuppressionOnly PathologyProfile = "suppressionOnly"
	PathologyAmbiguityOnly   PathologyProfile = "ambiguityOnly"
	PathologyBoth            PathologyProfile = "both"
)

// ClassificationKey is the primary key for an irreducible wait class.
type ClassificationKey struct {
	WaitDecompositionCodes []int
	PathologyProfile       PathologyProfile
}

// IrreducibleWaitClassification contains the reduced hand's decomposition
// codes, pathology profile, and stable legacy integer classification ID.
type IrreducibleWaitClassification struct {
	WaitDecompositionCodes []int
	PathologyProfile       PathologyProfile
	ClassificationID       int
}

// Key returns the decomposition-and-pathology key for the classification.
func (c IrreducibleWaitClassification) Key() ClassificationKey {
	return ClassificationKey{
		WaitDecompositionCodes: append([]int(nil), c.WaitDecompositionCodes...),
		PathologyProfile:       c.PathologyProfile,
	}
}

type handCounts [tileTypeCount]uint8

type component struct {
	kind  int
	value int
}

const (
	pairComponent = iota
	sequenceComponent
	tripletComponent
)

const (
	tankiPrime   = 2
	toitsuPrime  = 3
	ryanmenPrime = 5
	kanchanPrime = 7
	penchanPrime = 11
	shuntsuPrime = 13
	koutsuPrime  = 17
)

type waitAnalysis struct {
	codes []int
	cores map[string]struct{}
	waits uint64
}

type analyzer struct {
	analysisCache       map[handCounts]waitAnalysis
	profileCache        map[handCounts]PathologyProfile
	idCache             map[handCounts][]int
	classificationCache map[handCounts]map[classificationIdentity]IrreducibleWaitClassification
}

type classificationIdentity struct {
	id      int
	profile PathologyProfile
}

func newAnalyzer() *analyzer {
	return &analyzer{
		analysisCache:       make(map[handCounts]waitAnalysis),
		profileCache:        make(map[handCounts]PathologyProfile),
		idCache:             make(map[handCounts][]int),
		classificationCache: make(map[handCounts]map[classificationIdentity]IrreducibleWaitClassification),
	}
}

func countsFromTileIDs(tileIDs []int) (handCounts, error) {
	var counts handCounts
	switch len(tileIDs) {
	case 4, 7, 10, 13:
	default:
		return counts, fmt.Errorf("%w: hand size must be one of 4, 7, 10, or 13", ErrInvalidHand)
	}

	var seen [physicalTileCount]bool
	for _, tileID := range tileIDs {
		if tileID < 0 || tileID >= physicalTileCount {
			return counts, fmt.Errorf("%w: Tenhou tile ID %d is outside 0..135", ErrInvalidHand, tileID)
		}
		if seen[tileID] {
			return counts, fmt.Errorf("%w: physical tile ID %d occurs more than once", ErrInvalidHand, tileID)
		}
		seen[tileID] = true
		counts[tileID/4]++
	}
	return counts, nil
}

func countsFromInt37(int37Tiles []int) (handCounts, error) {
	var counts handCounts
	switch len(int37Tiles) {
	case 4, 7, 10, 13:
	default:
		return counts, fmt.Errorf("%w: hand size must be one of 4, 7, 10, or 13", ErrInvalidHand)
	}

	var redFives [3]uint8
	var ordinaryFives [3]uint8
	for _, tile := range int37Tiles {
		if tile < 0 || tile > 36 {
			return counts, fmt.Errorf("%w: Int37 value %d is outside 0..36", ErrInvalidHand, tile)
		}

		kind := 0
		suit := -1
		switch {
		case tile == 0:
			kind, suit = 4, 0
			redFives[suit]++
		case tile >= 1 && tile <= 9:
			kind = tile - 1
			if tile == 5 {
				suit = 0
				ordinaryFives[suit]++
			}
		case tile == 10:
			kind, suit = 13, 1
			redFives[suit]++
		case tile >= 11 && tile <= 19:
			kind = tile - 2
			if tile == 15 {
				suit = 1
				ordinaryFives[suit]++
			}
		case tile == 20:
			kind, suit = 22, 2
			redFives[suit]++
		case tile >= 21 && tile <= 29:
			kind = tile - 3
			if tile == 25 {
				suit = 2
				ordinaryFives[suit]++
			}
		default:
			kind = tile - 3
		}

		counts[kind]++
		if counts[kind] > 4 {
			return handCounts{}, fmt.Errorf("%w: Int37 tile kind %d occurs more than four times", ErrInvalidHand, kind)
		}
		if suit >= 0 {
			if redFives[suit] > 1 {
				return handCounts{}, fmt.Errorf("%w: red five in suit %d occurs more than once", ErrInvalidHand, suit)
			}
			if ordinaryFives[suit] > 3 {
				return handCounts{}, fmt.Errorf("%w: ordinary five in suit %d occurs more than three times", ErrInvalidHand, suit)
			}
			if int(redFives[suit])+int(ordinaryFives[suit]) > 4 {
				return handCounts{}, fmt.Errorf("%w: fives in suit %d occur more than four times", ErrInvalidHand, suit)
			}
		}
	}
	return counts, nil
}

// WaitDecompositionCodes returns the sorted waitDecompositionCodes for a hand.
// tileIDs are Tenhou 136-tile physical IDs (0 through 135); red fives map to
// their ordinary five tile type. Supported hand sizes are 4, 7, 10, and 13.
func WaitDecompositionCodes(tileIDs []int) ([]int, error) {
	counts, err := countsFromTileIDs(tileIDs)
	if err != nil {
		return nil, err
	}
	return waitDecompositionCodesFromCounts(counts)
}

// WaitDecompositionCodesInt37 returns sorted wait-decomposition codes for closed
// tiles encoded as Int37 values (0..36), with lengths 4, 7, 10, or 13. Repeated
// values represent copies; red fives project to ordinary five kinds. Schema:
// aka37-int37/v1.
func WaitDecompositionCodesInt37(int37Tiles []int) ([]int, error) {
	counts, err := countsFromInt37(int37Tiles)
	if err != nil {
		return nil, err
	}
	return waitDecompositionCodesFromCounts(counts)
}

func waitDecompositionCodesFromCounts(counts handCounts) ([]int, error) {
	result := newAnalyzer().analyze(counts)
	if len(result.codes) == 0 {
		return nil, ErrNotTenpai
	}
	return append([]int(nil), result.codes...), nil
}

// PathologyProfileForHand classifies pathologies in any supported standard-form
// tenpai hand, including reducible hands. It compares sets of wait tile types
// and wait cores before and after removing one complete sequence or triplet.
func PathologyProfileForHand(tileIDs []int) (PathologyProfile, error) {
	counts, err := countsFromTileIDs(tileIDs)
	if err != nil {
		return "", err
	}
	return pathologyProfileForCounts(counts)
}

// PathologyProfileForHandInt37 checks pathology marks on closed tiles encoded
// as Int37 values (0..36), with lengths 4, 7, 10, or 13. Repeated values
// represent copies; red fives project to ordinary five kinds. Schema:
// aka37-int37/v1.
func PathologyProfileForHandInt37(int37Tiles []int) (PathologyProfile, error) {
	counts, err := countsFromInt37(int37Tiles)
	if err != nil {
		return "", err
	}
	return pathologyProfileForCounts(counts)
}

func pathologyProfileForCounts(counts handCounts) (PathologyProfile, error) {
	a := newAnalyzer()
	if len(a.analyze(counts).codes) == 0 {
		return "", ErrNotTenpai
	}
	return a.pathologyProfile(counts), nil
}

// ClassifyIrreducibleWait removes complete melds while preserving the exact
// wait-core set and returns the resulting irreducible class. The returned
// pathology profile belongs to that irreducible hand.
func ClassifyIrreducibleWait(tileIDs []int) (IrreducibleWaitClassification, error) {
	counts, err := countsFromTileIDs(tileIDs)
	if err != nil {
		return IrreducibleWaitClassification{}, err
	}
	return classifyIrreducibleWaitFromCounts(counts)
}

// ClassifyIrreducibleWaitInt37 classifies closed tiles encoded as Int37 values
// (0..36), with lengths 4, 7, 10, or 13. Repeated values represent copies; red
// fives project to ordinary five kinds. Schema: aka37-int37/v1.
func ClassifyIrreducibleWaitInt37(int37Tiles []int) (IrreducibleWaitClassification, error) {
	counts, err := countsFromInt37(int37Tiles)
	if err != nil {
		return IrreducibleWaitClassification{}, err
	}
	return classifyIrreducibleWaitFromCounts(counts)
}

func classifyIrreducibleWaitFromCounts(counts handCounts) (IrreducibleWaitClassification, error) {
	a := newAnalyzer()
	original := a.analyze(counts)
	if len(original.codes) == 0 {
		return IrreducibleWaitClassification{}, ErrNotTenpai
	}

	classifications := a.irreducibleClassifications(counts)
	if len(classifications) == 0 {
		return IrreducibleWaitClassification{}, fmt.Errorf(
			"%w: no fixed classification reachable from (%d tiles, %v)",
			ErrUnknownClassification, countTiles(counts), original.codes,
		)
	}
	if len(classifications) != 1 {
		ids := make([]int, 0, len(classifications))
		for _, classification := range classifications {
			ids = append(ids, classification.ClassificationID)
		}
		sort.Ints(ids)
		return IrreducibleWaitClassification{}, fmt.Errorf("%w: reached IDs %v", ErrAmbiguousReduction, ids)
	}
	for _, classification := range classifications {
		return classification, nil
	}
	panic("unreachable")
}

// ClassifyIrreducibleWaitID returns the stable decomposition-code-only global
// ID, without distinguishing pathology profiles.
func ClassifyIrreducibleWaitID(tileIDs []int) (int, error) {
	counts, err := countsFromTileIDs(tileIDs)
	if err != nil {
		return 0, err
	}
	return classifyIrreducibleWaitIDFromCounts(counts)
}

// ClassifyIrreducibleWaitIDInt37 returns the stable classification ID for
// closed tiles encoded as Int37 values (0..36), with lengths 4, 7, 10, or 13.
// Repeated values represent copies; red fives project to ordinary five kinds.
// Schema: aka37-int37/v1.
func ClassifyIrreducibleWaitIDInt37(int37Tiles []int) (int, error) {
	counts, err := countsFromInt37(int37Tiles)
	if err != nil {
		return 0, err
	}
	return classifyIrreducibleWaitIDFromCounts(counts)
}

func classifyIrreducibleWaitIDFromCounts(counts handCounts) (int, error) {
	a := newAnalyzer()
	original := a.analyze(counts)
	if len(original.codes) == 0 {
		return 0, ErrNotTenpai
	}
	ids := a.irreducibleClassificationIDs(counts)
	if len(ids) == 0 {
		return 0, fmt.Errorf(
			"%w: no fixed classification reachable from (%d tiles, %v)",
			ErrUnknownClassification, countTiles(counts), original.codes,
		)
	}
	if len(ids) != 1 {
		sort.Ints(ids)
		return 0, fmt.Errorf("%w: reached IDs %v", ErrAmbiguousReduction, ids)
	}
	if ids[0] < 0 {
		return 0, fmt.Errorf(
			"%w: no fixed classification reachable from (%d tiles, %v)",
			ErrUnknownClassification, countTiles(counts), original.codes,
		)
	}
	return ids[0], nil
}

func (a *analyzer) analyze(counts handCounts) waitAnalysis {
	if cached, ok := a.analysisCache[counts]; ok {
		return cached
	}
	codeEntries := make(map[[2]int]struct{})
	cores := make(map[string]struct{})
	var waits uint64

	for wait, count := range counts {
		if count == 4 {
			continue
		}
		completed := counts
		completed[wait]++
		for _, partition := range winningPartitions(completed) {
			for selected, part := range partition {
				if !componentContains(part, wait) {
					continue
				}
				incompletePrime, incompleteTiles := incompleteComponent(part, wait)
				coreComponents := []coreComponent{{kind: incompletePrime, tiles: incompleteTiles}}
				factors := 1
				for index, candidate := range partition {
					if index == selected {
						factors *= incompletePrime
						continue
					}
					switch candidate.kind {
					case pairComponent:
						factors *= toitsuPrime
						coreComponents = append(coreComponents, coreComponent{
							kind: toitsuPrime, tiles: []int{candidate.value, candidate.value},
						})
					case sequenceComponent:
						factors *= shuntsuPrime
					case tripletComponent:
						factors *= koutsuPrime
					}
				}
				codeEntries[[2]int{wait, factors}] = struct{}{}
				sort.Slice(coreComponents, func(i, j int) bool {
					return coreComponentLess(coreComponents[i], coreComponents[j])
				})
				cores[encodeCore(wait, coreComponents)] = struct{}{}
				waits |= uint64(1) << uint(wait)
			}
		}
	}

	codes := make([]int, 0, len(codeEntries))
	for entry := range codeEntries {
		codes = append(codes, entry[1])
	}
	sort.Ints(codes)
	result := waitAnalysis{codes: codes, cores: cores, waits: waits}
	a.analysisCache[counts] = result
	return result
}

func winningPartitions(counts handCounts) [][]component {
	total := countTiles(counts)
	if total < 2 || (total-2)%3 != 0 {
		return nil
	}
	meldCount := (total - 2) / 3
	var result [][]component
	for pairTile, count := range counts {
		if count < 2 {
			continue
		}
		remaining := counts
		remaining[pairTile] -= 2
		for _, melds := range meldPartitions(remaining, meldCount) {
			partition := make([]component, 1, len(melds)+1)
			partition[0] = component{kind: pairComponent, value: pairTile}
			partition = append(partition, melds...)
			result = append(result, partition)
		}
	}
	return result
}

func meldPartitions(counts handCounts, meldCount int) [][]component {
	if meldCount == 0 {
		if countTiles(counts) == 0 {
			return [][]component{{}}
		}
		return nil
	}
	tile := -1
	for index, count := range counts {
		if count != 0 {
			tile = index
			break
		}
	}
	if tile < 0 {
		return nil
	}

	var result [][]component
	if counts[tile] >= 3 {
		remaining := counts
		remaining[tile] -= 3
		for _, rest := range meldPartitions(remaining, meldCount-1) {
			result = append(result, prependComponent(component{kind: tripletComponent, value: tile}, rest))
		}
	}
	if tile < 27 && tile%9 <= 6 && counts[tile+1] != 0 && counts[tile+2] != 0 {
		remaining := counts
		remaining[tile]--
		remaining[tile+1]--
		remaining[tile+2]--
		for _, rest := range meldPartitions(remaining, meldCount-1) {
			result = append(result, prependComponent(component{kind: sequenceComponent, value: tile}, rest))
		}
	}
	return result
}

func prependComponent(head component, tail []component) []component {
	result := make([]component, 1, len(tail)+1)
	result[0] = head
	return append(result, tail...)
}

func componentContains(part component, tile int) bool {
	if part.kind == sequenceComponent {
		return part.value <= tile && tile <= part.value+2
	}
	return part.value == tile
}

func incompleteComponent(part component, wait int) (int, []int) {
	switch part.kind {
	case pairComponent:
		return tankiPrime, []int{part.value}
	case tripletComponent:
		return toitsuPrime, []int{part.value, part.value}
	default:
		offset := wait - part.value
		if offset == 1 {
			return kanchanPrime, []int{part.value, part.value + 2}
		}
		if (offset == 0 && part.value%9 == 6) || (offset == 2 && part.value%9 == 0) {
			if offset == 0 {
				return penchanPrime, []int{part.value + 1, part.value + 2}
			}
			return penchanPrime, []int{part.value, part.value + 1}
		}
		if offset == 0 {
			return ryanmenPrime, []int{part.value + 1, part.value + 2}
		}
		return ryanmenPrime, []int{part.value, part.value + 1}
	}
}

type coreComponent struct {
	kind  int
	tiles []int
}

func coreComponentLess(first, second coreComponent) bool {
	if first.kind != second.kind {
		return first.kind < second.kind
	}
	for index := 0; index < len(first.tiles) && index < len(second.tiles); index++ {
		if first.tiles[index] != second.tiles[index] {
			return first.tiles[index] < second.tiles[index]
		}
	}
	return len(first.tiles) < len(second.tiles)
}

func encodeCore(wait int, components []coreComponent) string {
	var encoded strings.Builder
	encoded.Grow(2 + len(components)*4)
	encoded.WriteByte(byte(wait))
	encoded.WriteByte(byte(len(components)))
	for _, part := range components {
		encoded.WriteByte(byte(part.kind))
		encoded.WriteByte(byte(len(part.tiles)))
		for _, tile := range part.tiles {
			encoded.WriteByte(byte(tile))
		}
	}
	return encoded.String()
}

func (a *analyzer) pathologyProfile(counts handCounts) PathologyProfile {
	if cached, ok := a.profileCache[counts]; ok {
		return cached
	}
	original := a.analyze(counts)
	hasSuppression := false
	hasAmbiguity := false
	for _, remaining := range mentsuReductions(counts) {
		reduced := a.analyze(remaining)
		if len(reduced.codes) == 0 {
			continue
		}
		if original.waits&reduced.waits == original.waits && original.waits != reduced.waits {
			hasSuppression = true
		} else if original.waits == reduced.waits &&
			len(reduced.cores) < len(original.cores) && coreSubset(reduced.cores, original.cores) {
			hasAmbiguity = true
		}
	}
	profile := PathologyHealthy
	switch {
	case hasSuppression && hasAmbiguity:
		profile = PathologyBoth
	case hasSuppression:
		profile = PathologySuppressionOnly
	case hasAmbiguity:
		profile = PathologyAmbiguityOnly
	}
	a.profileCache[counts] = profile
	return profile
}

func (a *analyzer) irreducibleClassificationIDs(counts handCounts) []int {
	if cached, ok := a.idCache[counts]; ok {
		return append([]int(nil), cached...)
	}
	original := a.analyze(counts)
	var preserving []handCounts
	for _, remaining := range mentsuReductions(counts) {
		reduced := a.analyze(remaining)
		if len(reduced.codes) != 0 && equalCores(original.cores, reduced.cores) {
			preserving = append(preserving, remaining)
		}
	}

	ids := make(map[int]struct{})
	if len(preserving) != 0 {
		for _, remaining := range preserving {
			for _, id := range a.irreducibleClassificationIDs(remaining) {
				if id >= 0 {
					ids[id] = struct{}{}
				}
			}
		}
	} else if id, ok := lookupClassification(countTiles(counts), original.codes); ok {
		ids[id] = struct{}{}
	} else {
		ids[-1] = struct{}{}
	}

	result := make([]int, 0, len(ids))
	for id := range ids {
		result = append(result, id)
	}
	sort.Ints(result)
	a.idCache[counts] = append([]int(nil), result...)
	return result
}

func (a *analyzer) irreducibleClassifications(
	counts handCounts,
) map[classificationIdentity]IrreducibleWaitClassification {
	if cached, ok := a.classificationCache[counts]; ok {
		return cached
	}
	original := a.analyze(counts)
	var preserving []handCounts
	for _, remaining := range mentsuReductions(counts) {
		reduced := a.analyze(remaining)
		if len(reduced.codes) != 0 && equalCores(original.cores, reduced.cores) {
			preserving = append(preserving, remaining)
		}
	}

	classifications := make(map[classificationIdentity]IrreducibleWaitClassification)
	if len(preserving) != 0 {
		for _, remaining := range preserving {
			for key, classification := range a.irreducibleClassifications(remaining) {
				classifications[key] = classification
			}
		}
	} else if id, ok := lookupClassification(countTiles(counts), original.codes); ok {
		classification := IrreducibleWaitClassification{
			WaitDecompositionCodes: append([]int(nil), original.codes...),
			PathologyProfile:       a.pathologyProfile(counts),
			ClassificationID:       id,
		}
		key := classificationIdentity{id: id, profile: classification.PathologyProfile}
		classifications[key] = classification
	}
	a.classificationCache[counts] = classifications
	return classifications
}

func lookupClassification(tileCount int, codes []int) (int, bool) {
	var key strings.Builder
	key.WriteString(strconv.Itoa(tileCount))
	key.WriteByte('|')
	for index, code := range codes {
		if index != 0 {
			key.WriteByte(',')
		}
		key.WriteString(strconv.Itoa(code))
	}
	id, ok := irreducibleClassificationIDs[key.String()]
	return id, ok
}

func countTiles(counts handCounts) int {
	total := 0
	for _, count := range counts {
		total += int(count)
	}
	return total
}

func mentsuReductions(counts handCounts) []handCounts {
	reductions := make(map[handCounts]struct{})
	for tile, count := range counts {
		if count >= 3 {
			remaining := counts
			remaining[tile] -= 3
			reductions[remaining] = struct{}{}
		}
	}
	for start := 0; start < 27; start++ {
		if start%9 <= 6 && counts[start] > 0 && counts[start+1] > 0 && counts[start+2] > 0 {
			remaining := counts
			remaining[start]--
			remaining[start+1]--
			remaining[start+2]--
			reductions[remaining] = struct{}{}
		}
	}
	result := make([]handCounts, 0, len(reductions))
	for reduction := range reductions {
		result = append(result, reduction)
	}
	sort.Slice(result, func(i, j int) bool {
		for tile := 0; tile < tileTypeCount; tile++ {
			if result[i][tile] != result[j][tile] {
				return result[i][tile] < result[j][tile]
			}
		}
		return false
	})
	return result
}

func equalCores(first, second map[string]struct{}) bool {
	if len(first) != len(second) {
		return false
	}
	return coreSubset(first, second)
}

func coreSubset(subset, superset map[string]struct{}) bool {
	for core := range subset {
		if _, ok := superset[core]; !ok {
			return false
		}
	}
	return true
}
