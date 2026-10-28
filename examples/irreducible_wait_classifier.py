"""Classify standard-form irreducible waits from Tenhou 136-tile IDs.

The primary key combines wait-decomposition codes with a pathology profile.
Red fives need no special case: dividing a Tenhou physical tile ID by four
maps every copy, including a red five, to the corresponding one of the 34
tile types.
"""

from __future__ import annotations

from bisect import bisect_left
from dataclasses import dataclass
from enum import Enum
from functools import lru_cache
from math import prod
from typing import Final, Iterable, Sequence

from irreducible_wait_classification_table import (
    CLASSIFICATION_CODE_LISTS,
    CLASSIFICATION_ID_OFFSETS,
)


class WaitClassificationError(ValueError):
    """Base class for invalid or unsupported classification input."""


class InvalidHandError(WaitClassificationError):
    """The input is not a legal supported Tenhou hand."""


class NotTenpaiError(WaitClassificationError):
    """The input is not a standard-form tenpai hand."""


class UnknownIrreducibleClassificationError(WaitClassificationError):
    """The hand's code list is absent from the fixed irreducible table."""


class AmbiguousReductionError(WaitClassificationError):
    """Wait-core-preserving reductions reached different classifications."""


_SUPPORTED_HAND_SIZES: Final = frozenset((4, 7, 10, 13))
_TILE_TYPE_COUNT: Final = 34
_PHYSICAL_TILE_COUNT: Final = 136

_PAIR: Final = 0
_SEQUENCE: Final = 1
_TRIPLET: Final = 2

_TANKI_PRIME: Final = 2
_TOITSU_PRIME: Final = 3
_RYANMEN_PRIME: Final = 5
_KANCHAN_PRIME: Final = 7
_PENCHAN_PRIME: Final = 11
_SHUNTSU_PRIME: Final = 13
_KOUTSU_PRIME: Final = 17

Component = tuple[int, int]
Codes = tuple[int, ...]
WaitCore = tuple[int, tuple[tuple[int, tuple[int, ...]], ...]]


class PathologyProfile(str, Enum):
    """The pathology marks found by inspecting single completed-meld removals."""

    HEALTHY = "healthy"
    SUPPRESSION_ONLY = "suppressionOnly"
    AMBIGUITY_ONLY = "ambiguityOnly"
    BOTH = "both"


@dataclass(frozen=True)
class IrreducibleWaitClassification:
    """Primary classification key for an irreducible tenpai hand."""

    wait_decomposition_codes: Codes
    pathology_profile: PathologyProfile
    classification_id: int

    @property
    def key(self) -> tuple[Codes, PathologyProfile]:
        return self.wait_decomposition_codes, self.pathology_profile


def _tenhou_tiles_to_counts(tile_ids: Sequence[int]) -> tuple[int, ...]:
    if len(tile_ids) not in _SUPPORTED_HAND_SIZES:
        raise InvalidHandError("hand size must be one of 4, 7, 10, or 13")

    seen: set[int] = set()
    counts = [0] * _TILE_TYPE_COUNT
    for tile_id in tile_ids:
        if isinstance(tile_id, bool) or not isinstance(tile_id, int):
            raise InvalidHandError(f"tile ID must be an integer: {tile_id!r}")
        if not 0 <= tile_id < _PHYSICAL_TILE_COUNT:
            raise InvalidHandError(f"Tenhou tile ID is outside 0..135: {tile_id}")
        if tile_id in seen:
            raise InvalidHandError(f"physical tile ID occurs more than once: {tile_id}")
        seen.add(tile_id)
        counts[tile_id // 4] += 1
    return tuple(counts)


def _is_numbered(tile: int) -> bool:
    return tile < 27


@lru_cache(maxsize=None)
def _meld_partitions(counts: tuple[int, ...], meld_count: int) -> tuple[tuple[Component, ...], ...]:
    if meld_count == 0:
        return ((),) if not any(counts) else ()

    try:
        tile = next(index for index, count in enumerate(counts) if count)
    except StopIteration:
        return ()

    results: list[tuple[Component, ...]] = []
    if counts[tile] >= 3:
        remaining = list(counts)
        remaining[tile] -= 3
        for rest in _meld_partitions(tuple(remaining), meld_count - 1):
            results.append(((_TRIPLET, tile),) + rest)

    rank = tile % 9
    if _is_numbered(tile) and rank <= 6 and counts[tile + 1] and counts[tile + 2]:
        remaining = list(counts)
        remaining[tile] -= 1
        remaining[tile + 1] -= 1
        remaining[tile + 2] -= 1
        for rest in _meld_partitions(tuple(remaining), meld_count - 1):
            results.append(((_SEQUENCE, tile),) + rest)

    return tuple(results)


def _winning_partitions(counts: tuple[int, ...]) -> Iterable[tuple[Component, ...]]:
    meld_count = (sum(counts) - 2) // 3
    for pair_tile, count in enumerate(counts):
        if count < 2:
            continue
        remaining = list(counts)
        remaining[pair_tile] -= 2
        for melds in _meld_partitions(tuple(remaining), meld_count):
            yield ((_PAIR, pair_tile),) + melds


def _component_contains(component: Component, tile: int) -> bool:
    kind, value = component
    if kind == _SEQUENCE:
        return value <= tile <= value + 2
    return value == tile


def _component_prime_after_removing_wait(component: Component, wait: int) -> int:
    kind, value = component
    if kind == _PAIR:
        return _TANKI_PRIME
    if kind == _TRIPLET:
        return _TOITSU_PRIME

    offset = wait - value
    if offset == 1:
        return _KANCHAN_PRIME
    if (offset == 0 and value % 9 == 6) or (offset == 2 and value % 9 == 0):
        return _PENCHAN_PRIME
    return _RYANMEN_PRIME


def _complete_component_prime(component: Component) -> int:
    if component[0] == _PAIR:
        return _TOITSU_PRIME
    return _SHUNTSU_PRIME if component[0] == _SEQUENCE else _KOUTSU_PRIME


def _incomplete_component(component: Component, wait: int) -> tuple[int, tuple[int, ...]]:
    prime = _component_prime_after_removing_wait(component, wait)
    kind, value = component
    if kind == _PAIR:
        tiles = (value,)
    elif kind == _TRIPLET:
        tiles = (value, value)
    else:
        tiles = tuple(tile for tile in (value, value + 1, value + 2) if tile != wait)
    return prime, tiles


@lru_cache(maxsize=None)
def _analyze_counts(
    counts: tuple[int, ...],
) -> tuple[Codes, frozenset[tuple[int, tuple[tuple[int, tuple[int, ...]], ...]]]]:
    entries: set[tuple[int, int]] = set()
    cores: set[tuple[int, tuple[tuple[int, tuple[int, ...]], ...]]] = set()

    for wait in range(_TILE_TYPE_COUNT):
        if counts[wait] == 4:
            continue
        completed = list(counts)
        completed[wait] += 1
        for partition in _winning_partitions(tuple(completed)):
            for selected, component in enumerate(partition):
                if not _component_contains(component, wait):
                    continue
                incomplete_prime, incomplete_tiles = _incomplete_component(component, wait)
                core_components = [(incomplete_prime, incomplete_tiles)]
                core_components.extend(
                    (_TOITSU_PRIME, (candidate[1], candidate[1]))
                    for index, candidate in enumerate(partition)
                    if index != selected and candidate[0] == _PAIR
                )
                factors = [
                    incomplete_prime
                    if index == selected
                    else _complete_component_prime(candidate)
                    for index, candidate in enumerate(partition)
                ]
                entries.add((wait, prod(factors)))
                cores.add((wait, tuple(sorted(core_components))))

    return tuple(sorted(code for _, code in entries)), frozenset(cores)


def wait_decomposition_codes(tile_ids: Sequence[int]) -> Codes:
    """Return the sorted ``waitDecompositionCodes`` list for a Tenhou hand.

    ``tile_ids`` uses Tenhou's 136 physical tile IDs, 0 through 135.  Supported
    hand sizes are 4, 7, 10, and 13.  A non-tenpai hand raises
    :class:`NotTenpaiError`.
    """

    codes, _ = _analyze_counts(_tenhou_tiles_to_counts(tile_ids))
    if not codes:
        raise NotTenpaiError("hand is not a standard-form tenpai hand")
    return codes


def _mentsu_reductions(counts: tuple[int, ...]) -> tuple[tuple[int, ...], ...]:
    reductions: set[tuple[int, ...]] = set()
    for tile, count in enumerate(counts):
        if count >= 3:
            remaining = list(counts)
            remaining[tile] -= 3
            reductions.add(tuple(remaining))
    for start in range(27):
        if start % 9 <= 6 and counts[start] and counts[start + 1] and counts[start + 2]:
            remaining = list(counts)
            remaining[start] -= 1
            remaining[start + 1] -= 1
            remaining[start + 2] -= 1
            reductions.add(tuple(remaining))
    return tuple(sorted(reductions))


def _waits(cores: frozenset[WaitCore]) -> frozenset[int]:
    return frozenset(wait for wait, _ in cores)


@lru_cache(maxsize=None)
def _pathology_profile(counts: tuple[int, ...]) -> PathologyProfile:
    _, original_cores = _analyze_counts(counts)
    original_waits = _waits(original_cores)
    has_suppression = False
    has_redundant_ambiguity = False

    for remaining in _mentsu_reductions(counts):
        codes, remaining_cores = _analyze_counts(remaining)
        if not codes:
            continue
        remaining_waits = _waits(remaining_cores)
        if original_waits < remaining_waits:
            has_suppression = True
        elif (
            remaining_waits == original_waits
            and len(remaining_cores) < len(original_cores)
            and remaining_cores < original_cores
        ):
            has_redundant_ambiguity = True

    if has_suppression and has_redundant_ambiguity:
        return PathologyProfile.BOTH
    if has_suppression:
        return PathologyProfile.SUPPRESSION_ONLY
    if has_redundant_ambiguity:
        return PathologyProfile.AMBIGUITY_ONLY
    return PathologyProfile.HEALTHY


def _lookup_classification(tile_count: int, codes: Codes) -> int | None:
    table = CLASSIFICATION_CODE_LISTS.get(tile_count)
    if table is None:
        return None
    local_id = bisect_left(table, codes)
    if local_id == len(table) or table[local_id] != codes:
        return None
    return CLASSIFICATION_ID_OFFSETS[tile_count] + local_id


@lru_cache(maxsize=None)
def _irreducible_classification_ids(counts: tuple[int, ...]) -> frozenset[int]:
    codes, original_cores = _analyze_counts(counts)
    preserving_reductions = tuple(
        remaining
        for remaining in _mentsu_reductions(counts)
        if _analyze_counts(remaining)[0] and _analyze_counts(remaining)[1] == original_cores
    )
    if preserving_reductions:
        return frozenset(
            classification_id
            for remaining in preserving_reductions
            for classification_id in _irreducible_classification_ids(remaining)
        )

    classification_id = _lookup_classification(sum(counts), codes)
    return frozenset() if classification_id is None else frozenset((classification_id,))


@lru_cache(maxsize=None)
def _irreducible_classifications(
    counts: tuple[int, ...],
) -> frozenset[IrreducibleWaitClassification]:
    codes, original_cores = _analyze_counts(counts)
    preserving_reductions = tuple(
        remaining
        for remaining in _mentsu_reductions(counts)
        if _analyze_counts(remaining)[0] and _analyze_counts(remaining)[1] == original_cores
    )
    if preserving_reductions:
        return frozenset(
            classification
            for remaining in preserving_reductions
            for classification in _irreducible_classifications(remaining)
        )

    classification_id = _lookup_classification(sum(counts), codes)
    if classification_id is None:
        return frozenset()
    return frozenset(
        (
            IrreducibleWaitClassification(
                wait_decomposition_codes=codes,
                pathology_profile=_pathology_profile(counts),
                classification_id=classification_id,
            ),
        )
    )


def classify_irreducible_wait(tile_ids: Sequence[int]) -> IrreducibleWaitClassification:
    """Reduce a tenpai hand and return its code-and-pathology classification.

    Wait-core-preserving complete melds are removed until an irreducible hand
    remains. The primary key is the sorted wait-decomposition-code list plus
    the four-valued pathology profile of that irreducible hand. The legacy
    integer ID is included as ``classification_id``. An unknown irreducible
    code list raises :class:`UnknownIrreducibleClassificationError`.
    """

    counts = _tenhou_tiles_to_counts(tile_ids)
    codes, _ = _analyze_counts(counts)
    if not codes:
        raise NotTenpaiError("hand is not a standard-form tenpai hand")
    classifications = _irreducible_classifications(counts)
    if not classifications:
        raise UnknownIrreducibleClassificationError(
            f"no fixed irreducible classification reachable from {(len(tile_ids), codes)}"
        )
    if len(classifications) != 1:
        raise AmbiguousReductionError(
            "wait-core-preserving reductions reached classifications "
            f"{sorted(classifications, key=lambda item: (item.wait_decomposition_codes, item.pathology_profile.value))}"
        )
    return next(iter(classifications))


def classify_irreducible_wait_id(tile_ids: Sequence[int]) -> int:
    """Return the legacy code-only global ID, without pathology-profile checks."""

    counts = _tenhou_tiles_to_counts(tile_ids)
    codes, _ = _analyze_counts(counts)
    if not codes:
        raise NotTenpaiError("hand is not a standard-form tenpai hand")
    classification_ids = _irreducible_classification_ids(counts)
    if not classification_ids:
        raise UnknownIrreducibleClassificationError(
            f"no fixed irreducible classification reachable from {(len(tile_ids), codes)}"
        )
    if len(classification_ids) != 1:
        raise AmbiguousReductionError(
            f"wait-core-preserving reductions reached IDs {sorted(classification_ids)}"
        )
    return next(iter(classification_ids))