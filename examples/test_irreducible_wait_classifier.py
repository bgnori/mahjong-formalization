from __future__ import annotations

import json
from bisect import bisect_left
from pathlib import Path
import re
import unittest

import irreducible_wait_classifier as classifier
from irreducible_wait_classification_table import (
    CLASSIFICATION_CODE_LISTS,
    CLASSIFICATION_ID_OFFSETS,
)


ROOT = Path(__file__).resolve().parent.parent
REPORTS = (
    (4, ROOT / "reports" / "four-tile-direct-report.json", 11),
    (7, ROOT / "reports" / "seven-tile-report.json", 49),
    (10, ROOT / "reports" / "ten-tile-report.json", 199),
    (13, ROOT / "reports" / "thirteen-tile-report.json", 708),
)
def tenhou_ids(mpsz: str) -> list[int]:
    result: list[int] = []
    copies_used: dict[int, int] = {}
    for digits, suit in re.findall(r"([0-9]+)([mpsz])", mpsz):
        base = {"m": 0, "p": 9, "s": 18, "z": 27}[suit]
        for digit in digits:
            rank = 5 if digit == "0" else int(digit)
            tile_type = base + rank - 1
            copy = copies_used.get(tile_type, 0)
            if copy >= 4:
                raise ValueError(f"too many copies in {mpsz}")
            result.append(tile_type * 4 + copy)
            copies_used[tile_type] = copy + 1
    return result


def report_groups(path: Path):
    report = json.loads(path.read_text(encoding="utf-8"))
    for group in report["irreducibleGroupsByWaitDecompositionCodes"]:
        yield tuple(group["waitDecompositionCodes"]), group["representativeTiles"]


class IrreducibleWaitClassifierTest(unittest.TestCase):
    def test_all_report_classifications_keep_their_fixed_ids(self) -> None:
        seen_ids: set[int] = set()
        for tile_count, path, expected_count in REPORTS:
            groups = list(report_groups(path))
            self.assertEqual(len(groups), expected_count)
            table = CLASSIFICATION_CODE_LISTS[tile_count]
            for codes, representative in groups:
                tile_ids = tenhou_ids(representative)
                self.assertEqual(classifier.wait_decomposition_codes(tile_ids), codes)
                local_id = bisect_left(table, codes)
                expected_id = CLASSIFICATION_ID_OFFSETS[tile_count] + local_id
                classification = classifier.classify_irreducible_wait(tile_ids)
                self.assertEqual(classification.wait_decomposition_codes, codes)
                self.assertEqual(classification.classification_id, expected_id)
                self.assertIsInstance(classification.pathology_profile, classifier.PathologyProfile)
                self.assertEqual(classifier.classify_irreducible_wait_id(tile_ids), expected_id)
                seen_ids.add(expected_id)
        self.assertEqual(seen_ids, set(range(967)))

    def test_wait_core_preserving_melds_reduce_recursively(self) -> None:
        hands = ["1223m", "1223m111z", "1223m111222z", "1223m111222333z"]
        self.assertEqual(
            [
                classifier.classify_irreducible_wait(tenhou_ids(hand)).classification_id
                for hand in hands
            ],
            [5, 5, 5, 5],
        )

    def test_reducible_four_tile_tanki_uses_base_class(self) -> None:
        result = classifier.classify_irreducible_wait(tenhou_ids("1114m"))
        self.assertEqual(result.classification_id, 967)
        self.assertEqual(result.pathology_profile, classifier.PathologyProfile.HEALTHY)

    def test_red_five_identity_is_ignored(self) -> None:
        ordinary_five = [48, 53, 54, 56]
        red_five = [48, 52, 54, 56]
        self.assertEqual(
            classifier.classify_irreducible_wait(ordinary_five),
            classifier.classify_irreducible_wait(red_five),
        )

    def test_pathology_profiles_match_lean_examples(self) -> None:
        expected_profiles = {
            "1111222234444m": classifier.PathologyProfile.BOTH,
            "89p11123456777s": classifier.PathologyProfile.AMBIGUITY_ONLY,
        }
        for hand, expected_profile in expected_profiles.items():
            with self.subTest(hand=hand):
                result = classifier.classify_irreducible_wait(tenhou_ids(hand))
                self.assertEqual(result.pathology_profile, expected_profile)

    def test_pathology_profile_refines_identical_decomposition_codes(self) -> None:
        healthy = classifier.classify_irreducible_wait(tenhou_ids("2333345777p"))
        ambiguous = classifier.classify_irreducible_wait(tenhou_ids("3335666678s"))
        self.assertEqual(healthy.wait_decomposition_codes, ambiguous.wait_decomposition_codes)
        self.assertEqual(healthy.classification_id, ambiguous.classification_id)
        self.assertEqual(healthy.pathology_profile, classifier.PathologyProfile.HEALTHY)
        self.assertEqual(ambiguous.pathology_profile, classifier.PathologyProfile.AMBIGUITY_ONLY)
        self.assertNotEqual(healthy.key, ambiguous.key)

    def test_invalid_and_non_tenpai_inputs(self) -> None:
        invalid_hands = ([0, 0, 4, 8], [0, 4, 8, 136], [0])
        for hand in invalid_hands:
            with self.subTest(hand=hand), self.assertRaises(classifier.InvalidHandError):
                classifier.classify_irreducible_wait(hand)
        with self.assertRaises(classifier.NotTenpaiError):
            classifier.classify_irreducible_wait([0, 1, 2, 3])


if __name__ == "__main__":
    unittest.main()