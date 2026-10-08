"""Compare the public Zenn T001-T026 list with this repository's classifiers."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from typing import Iterable

import irreducible_wait_classifier as classifier


@dataclass(frozen=True)
class ZennWaitPattern:
    pattern_id: str
    representative: str
    published_waits: str


ZENN_WAIT_PATTERNS = (
    ZennWaitPattern("T001", "2", "2"),
    ZennWaitPattern("T002", "1124", "3"),
    ZennWaitPattern("T003", "1123", "14"),
    ZennWaitPattern("T004", "1122", "12"),
    ZennWaitPattern("T005", "2345", "25"),
    ZennWaitPattern("T006", "2224", "34"),
    ZennWaitPattern("T007", "2223", "134"),
    ZennWaitPattern("T008", "1123456", "147"),
    ZennWaitPattern("T009", "1122234", "125"),
    ZennWaitPattern("T010", "2345678", "258"),
    ZennWaitPattern("T011", "2344567", "147"),
    ZennWaitPattern("T012", "2333456", "1247"),
    ZennWaitPattern("T013", "2333345", "1245"),
    ZennWaitPattern("T014", "2233344", "234"),
    ZennWaitPattern("T015", "2233334", "1245"),
    ZennWaitPattern("T016", "2224666", "345"),
    ZennWaitPattern("T017", "2224567", "347"),
    ZennWaitPattern("T018", "2224456", "347"),
    ZennWaitPattern("T019", "2223457", "67"),
    ZennWaitPattern("T020", "2223456", "13467"),
    ZennWaitPattern("T021", "2223445", "346"),
    ZennWaitPattern("T022", "2223444", "12345"),
    ZennWaitPattern("T023", "2223345", "1346"),
    ZennWaitPattern("T024", "2223344", "2345"),
    ZennWaitPattern("T025", "2223334", "2345"),
    ZennWaitPattern("T026", "2222344", "134"),
)


def analyze_hand(hand: Iterable[int]):
    counts = [0] * 34
    for rank in hand:
        if not 1 <= rank <= 9:
            raise ValueError(f"rank must be in 1..9: {rank}")
        counts[rank - 1] += 1
    return classifier._analyze_counts(tuple(counts))


def waits_from_cores(cores) -> tuple[int, ...]:
    return tuple(sorted({wait + 1 for wait, _ in cores}))


def translated_and_reflected_hands(representative: str) -> tuple[tuple[int, ...], ...]:
    ranks = tuple(int(rank) for rank in representative)
    variants: set[tuple[int, ...]] = set()
    for direction in (1, -1):
        directed = tuple(direction * rank for rank in ranks)
        for offset in range(1 - min(directed), 10 - max(directed)):
            variants.add(tuple(sorted(rank + offset for rank in directed)))
    return tuple(sorted(variants))


def normalized_wait_core_signature(cores) -> tuple:
    used_tiles = [wait for wait, _ in cores]
    used_tiles.extend(
        tile
        for _, components in cores
        for _, tiles in components
        for tile in tiles
    )
    lowest = min(used_tiles)
    highest = max(used_tiles)

    def transform(reflect: bool) -> tuple:
        def transform_tile(tile: int) -> int:
            return highest - tile if reflect else tile - lowest

        return tuple(
            sorted(
                (
                    transform_tile(wait),
                    tuple(
                        sorted(
                            (
                                prime,
                                tuple(sorted(transform_tile(tile) for tile in tiles)),
                            )
                            for prime, tiles in components
                        )
                    ),
                )
                for wait, components in cores
            )
        )

    return min(transform(False), transform(True))


def refined_classification_key(hand: Iterable[int]) -> tuple:
    codes, cores = analyze_hand(hand)
    return codes, normalized_wait_core_signature(cores)


def placement_groups(pattern: ZennWaitPattern, refined: bool) -> dict[tuple, list[tuple[str, str]]]:
    groups: dict[tuple, list[tuple[str, str]]] = defaultdict(list)
    for hand in translated_and_reflected_hands(pattern.representative):
        codes, cores = analyze_hand(hand)
        key = (codes, normalized_wait_core_signature(cores)) if refined else codes
        hand_text = "".join(str(rank) for rank in hand)
        waits_text = "".join(str(rank) for rank in waits_from_cores(cores))
        groups[key].append((hand_text, waits_text))
    return dict(groups)


def main() -> None:
    print("ID\trepresentative\twaits\tcodes\tcodeClasses\trefinedClasses")
    for pattern in ZENN_WAIT_PATTERNS:
        hand = tuple(int(rank) for rank in pattern.representative)
        codes, cores = analyze_hand(hand)
        waits = "".join(str(rank) for rank in waits_from_cores(cores))
        print(
            f"{pattern.pattern_id}\t{pattern.representative}\t{waits}\t{list(codes)}\t"
            f"{len(placement_groups(pattern, refined=False))}\t"
            f"{len(placement_groups(pattern, refined=True))}"
        )


if __name__ == "__main__":
    main()
