from __future__ import annotations

from collections import Counter, defaultdict
import unittest

from zenn_wait_pattern_comparison import (
    ZENN_WAIT_PATTERNS,
    analyze_hand,
    placement_groups,
    refined_classification_key,
    waits_from_cores,
)


class ZennWaitPatternComparisonTest(unittest.TestCase):
    def test_transcribed_patterns_have_the_published_waits(self) -> None:
        self.assertEqual(
            Counter(map(len, (pattern.representative for pattern in ZENN_WAIT_PATTERNS))),
            {1: 1, 4: 6, 7: 19},
        )
        for pattern in ZENN_WAIT_PATTERNS:
            with self.subTest(pattern=pattern.pattern_id):
                _, cores = analyze_hand(map(int, pattern.representative))
                waits = "".join(str(rank) for rank in waits_from_cores(cores))
                self.assertEqual(waits, pattern.published_waits)

    def test_current_code_list_collides_for_t018_and_t026(self) -> None:
        patterns_by_codes: dict[tuple[int, ...], list[str]] = defaultdict(list)
        for pattern in ZENN_WAIT_PATTERNS:
            codes, _ = analyze_hand(map(int, pattern.representative))
            patterns_by_codes[codes].append(pattern.pattern_id)

        collisions = sorted(ids for ids in patterns_by_codes.values() if len(ids) > 1)
        self.assertEqual(collisions, [["T018", "T026"]])
        self.assertEqual(len(patterns_by_codes), 25)

    def test_normalized_wait_cores_distinguish_all_representatives(self) -> None:
        keys = {
            refined_classification_key(map(int, pattern.representative))
            for pattern in ZENN_WAIT_PATTERNS
        }
        self.assertEqual(len(keys), 26)

    def test_normalized_wait_cores_refine_all_placements(self) -> None:
        code_associations = 0
        code_owners: dict[tuple, set[str]] = defaultdict(set)
        refined_associations = 0
        refined_owners: dict[tuple, set[str]] = defaultdict(set)

        for pattern in ZENN_WAIT_PATTERNS:
            code_groups = placement_groups(pattern, refined=False)
            code_associations += len(code_groups)
            for key in code_groups:
                code_owners[key].add(pattern.pattern_id)

            refined_groups = placement_groups(pattern, refined=True)
            refined_associations += len(refined_groups)
            for key in refined_groups:
                refined_owners[key].add(pattern.pattern_id)

        self.assertEqual(code_associations, 44)
        self.assertEqual(len(code_owners), 42)
        self.assertEqual(
            [owners for owners in code_owners.values() if len(owners) > 1],
            [{"T018", "T026"}, {"T018", "T026"}],
        )
        self.assertEqual(refined_associations, 47)
        self.assertEqual(len(refined_owners), 47)


if __name__ == "__main__":
    unittest.main()
