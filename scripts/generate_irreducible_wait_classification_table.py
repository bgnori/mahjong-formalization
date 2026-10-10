"""Generate the Python irreducible wait classification table from reports."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "examples" / "irreducible_wait_classification_table.py"
REPORTS = (
    (4, ROOT / "reports" / "four-tile-direct-report.json", 11),
    (7, ROOT / "reports" / "seven-tile-report.json", 49),
    (10, ROOT / "reports" / "ten-tile-report.json", 199),
    (13, ROOT / "reports" / "thirteen-tile-report.json", 708),
)


def read_code_lists(path: Path, expected_count: int) -> list[tuple[int, ...]]:
    report = json.loads(path.read_text(encoding="utf-8"))
    values: list[tuple[int, ...]] = []
    for group in report["irreducibleGroupsByWaitDecompositionCodes"]:
        codes = tuple(group["waitDecompositionCodes"])
        if not all(isinstance(code, int) and code >= 0 for code in codes):
            raise ValueError(f"invalid code list in {path}: {codes}")
        if tuple(sorted(codes)) != codes:
            raise ValueError(f"unsorted code list in {path}: {codes}")
        values.append(codes)

    unique_values = sorted(set(values))
    if len(values) != expected_count or len(unique_values) != expected_count:
        raise ValueError(
            f"expected {expected_count} unique groups in {path}, "
            f"found {len(values)} rows and {len(unique_values)} unique values"
        )
    return unique_values


def tuple_literal(values: tuple[int, ...]) -> str:
    body = ", ".join(str(value) for value in values)
    if len(values) == 1:
        body += ","
    return f"({body})"


def main() -> None:
    tables = {
        tile_count: read_code_lists(path, expected_count)
        for tile_count, path, expected_count in REPORTS
    }
    offsets: dict[int, int] = {}
    next_id = 0
    for tile_count, _, _ in REPORTS:
        offsets[tile_count] = next_id
        next_id += len(tables[tile_count])
    tables[1] = [(2,)]
    offsets[1] = next_id
    next_id += 1

    lines = [
        '"""Generated irreducible wait classification tables.  Do not edit."""',
        "",
        "from typing import Final",
        "",
        "",
        "CLASSIFICATION_ID_OFFSETS: Final[dict[int, int]] = {",
    ]
    lines.extend(f"    {tile_count}: {offsets[tile_count]}," for tile_count, _, _ in REPORTS)
    lines.append(f"    1: {offsets[1]},")
    lines.extend(["}", "", "CLASSIFICATION_CODE_LISTS: Final[dict[int, tuple[tuple[int, ...], ...]]] = {"])
    for tile_count, _, _ in REPORTS:
        lines.append(f"    {tile_count}: (")
        lines.extend(f"        {tuple_literal(codes)}," for codes in tables[tile_count])
        lines.append("    ),")
    lines.extend(["    1: ((2,),),"])
    lines.extend(["}", ""])
    OUTPUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(ROOT)} with {next_id} classifications")


if __name__ == "__main__":
    main()