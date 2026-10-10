# MahjongComputations

This directory is for expensive or exhaustive Mahjong computations that should
not be part of normal `Mahjong` builds.

Build it explicitly when needed:

```bash
lake build MahjongComputations
```

Generate the four-tile JSON report:

```bash
lake build fourTileReport
```

The report is written to `reports/four-tile-direct-report.json`.

Generate the seven-tile JSON report:

```bash
lake build sevenTileReport
```

The report is written to `reports/seven-tile-report.json`.

Current modules:

- `Common.lean`: provides legal tile-multiset generation and counting, groups
  direct derivations and report statistics, and formats shared report values.
- `FourTile.lean`: enumerates all legal four-tile multisets and computes tenpai
  waits, reducibility, and wait decomposition codes.
- `FourTileReport.lean`: writes the exhaustive four-tile report as JSON.
- `SevenTile.lean`: folds all legal seven-tile multisets into aggregate wait
  report data without retaining every shape.
- `SevenTileReport.lean`: writes the exhaustive seven-tile aggregate report as
  JSON.

## Reducibility

A tenpai shape is reducible when a completed meld can be removed while the
remaining shape stays tenpai and preserves the set of wait cores; otherwise it
is irreducible.  For
example, `1223m` has wait-decomposition codes `[21, 26]` and is irreducible,
while `1233m` has codes `[26, 33]` and is also irreducible.  These cases are
covered by the regression tests in `MahjongTests/WaitDecompositionCode.lean`.