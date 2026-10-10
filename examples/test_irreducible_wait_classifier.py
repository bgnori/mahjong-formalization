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
                self.assertEqual(classifier.classify_irreducible_wait(tile_ids), expected_id)
                seen_ids.add(expected_id)
        self.assertEqual(seen_ids, set(range(967)))

    def test_wait_core_preserving_melds_reduce_recursively(self) -> None:
        hands = ["1223m", "1223m111z", "1223m111222z", "1223m111222333z"]
        self.assertEqual(
            [classifier.classify_irreducible_wait(tenhou_ids(hand)) for hand in hands],
            [5, 5, 5, 5],
        )

    def test_reducible_four_tile_tanki_uses_base_class(self) -> None:
        self.assertEqual(classifier.classify_irreducible_wait(tenhou_ids("1114m")), 967)

    def test_red_five_identity_is_ignored(self) -> None:
        ordinary_five = [48, 53, 54, 56]
        red_five = [48, 52, 54, 56]
        self.assertEqual(
            classifier.classify_irreducible_wait(ordinary_five),
            classifier.classify_irreducible_wait(red_five),
        )

    def test_invalid_and_non_tenpai_inputs(self) -> None:
        invalid_hands = ([0, 0, 4, 8], [0, 4, 8, 136], [0])
        for hand in invalid_hands:
            with self.subTest(hand=hand), self.assertRaises(classifier.InvalidHandError):
                classifier.classify_irreducible_wait(hand)
        with self.assertRaises(classifier.NotTenpaiError):
            classifier.classify_irreducible_wait([0, 1, 2, 3])


if __name__ == "__main__":
    unittest.main()