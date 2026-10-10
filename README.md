# Mahjong Formalization

A Lean 4 formalization and computational study of Mahjong mathematics. The project models tiles, tile patterns, standard-form wait semantics, wait cores, and exhaustive classifications, with machine-checked specifications and executable reports.

[日本語版はこちら](README.ja.md)

## Goals

- Formalize Mahjong structures and wait semantics with precise types and proofs.
- Use exhaustive computation to investigate and classify Mahjong waits.
- Keep examples executable with `example ... := by native_decide` where possible.
- Grow proofs alongside computation instead of treating documentation, tests, and implementation as separate artifacts.

## Project Layout

```text
.
├── Mahjong.lean           # Library entry point
├── Mahjong/               # Mahjong study modules
│   ├── Basic.lean
│   ├── Pattern.lean
│   ├── Hand.lean
│   ├── WaitCompletion.lean
│   ├── WaitCompletionFinder.lean
│   ├── WaitDecompositionCode.lean
│   ├── DirectWaitGeneration.lean
│   ├── Tenpai.lean
│   └── README.md
├── MahjongTests/          # Explicitly-built computational regression tests
├── MahjongComputations/   # Explicitly-built exhaustive computations and reports
├── docs/                  # Reading order and Lean/domain vocabulary
└── reports/               # Generated computation reports
```

## Build

```bash
lake build
```

To check the Mahjong modules explicitly:

```bash
lake build Mahjong
```

To run the computational regression tests:

```bash
lake build MahjongTests
```

To run expensive/exhaustive Mahjong computations:

```bash
lake build MahjongComputations
```

To generate the four-tile and seven-tile computation reports:

```bash
lake build fourTileReport
lake build sevenTileReport
```

The reports are written as JSON to `reports/four-tile-direct-report.json` and
`reports/seven-tile-report.json`. Reports share a versioned schema with named
summary fields, arrays of decomposition-code groups, and wait-count distributions.
Decomposition-code keys are strings so JSON viewers preserve their exact value.
To browse a report with Unicode Mahjong tiles, open
[`reports/report-viewer.html`](reports/report-viewer.html) and select or drop a JSON report.
Sections are navigated in a full-width main area, with pagination for long lists.

### GCP Batch pilot

The four-, seven-, ten-, and thirteen-tile reports can all be run through the
packaged GCP Batch + Spot VM workflow. After setting up the GCP resources described
in [`docs/remote-compute-gcp-batch.md`](docs/remote-compute-gcp-batch.md), run:

```bash
./scripts/remote-compute run four-tile      # 2 vCPU, connectivity check
./scripts/remote-compute run seven-tile     # 8 vCPU, parallel classification
./scripts/remote-compute run ten-tile       # 4 vCPU, exhaustive ten-tile report
./scripts/remote-compute run thirteen-tile  # 32 vCPU, multi-hour, checkpointed
```

Each job type picks its own machine size and defaults `--workers` to that machine's
vCPU count. Use `--detach` to submit without waiting; `status JOB_ID` checks progress
and `download JOB_ID` retrieves a successful report without overwriting existing files.
The thirteen-tile report finishes in roughly 7 hours 10 minutes on an `n2-standard-32`
Spot VM (measured 2026-10-09).

The ten- and thirteen-tile reports stream their external buckets and per-bucket
classification results to Cloud Storage, so a Spot preemption resumes from the last
checkpoint instead of restarting. Pass `--fresh` to discard stored checkpoints and
recompute from scratch. A resumed run reports different `waitCoreCache*` statistics
than an uninterrupted one, because the wait-core cache lives only in the process that
builds it; every other line of the report is unaffected.

The seven-tile report ends with a `calculationElapsedMs` line, so successive runs are
not byte-identical. Compare against `reports/seven-tile-report.json` with
`calculationElapsedMs` excluded.

### Dev containers by workload

Choose a dev container configuration based on the output being generated:

| Configuration | Workload | Minimum host requirements |
| --- | --- | --- |
| `development` | Normal editing, proofs, tests, and four-/seven-tile reports | None declared |
| `ten-tile` | Ten-tile report | 4 CPUs, 4 GB RAM, 32 GB storage |
| `thirteen-tile` | Thirteen-tile report | 16 CPUs, 64 GB RAM, 64 GB storage |

Select the configuration when opening the repository in a VS Code dev container or in the
Codespace creation options. Use `development` for normal local work and select a report-specific
configuration only when generating that report.

`hostRequirements` helps services such as Codespaces choose a suitable host; it does not impose
Docker resource limits. None of the configurations sets Docker CPU or memory limits. After creating
or rebuilding the container, verify the available resources with:

```bash
nproc
cat /sys/fs/cgroup/memory.max
df -h /workspaces
```

When changing configuration in an existing Codespace, select the new configuration and recreate the
container. Run long computations inside `tmux` and set the Codespaces idle timeout to 240 minutes. Terminal
output resets the idle timeout, so computations that may otherwise be silent for hours should emit
periodic progress. The measured ten-tile setup uses four workers:

```bash
lake exe ten-tile-report-gen --workers=4
```

Do not automatically use all CPUs for bucket classification: each classification
worker retains a bucket-sized hash map. A suitable initial command is:

```bash
lake exe thirteen-tile-report-gen --generation-workers=16 --classification-workers=8 --buckets=256
```

If organization policy offers a 32-core machine, generation workers can be raised to 32.

After generation completes, `.lake/build/thirteen-tile-buckets/generation.done` records the phase
boundary. Re-running with the same settings reuses those buckets if classification was interrupted.
The wait-core cache and individual bucket results are not checkpointed. Remove the bucket directory
to force regeneration.

To check a single file directly:

```bash
lake env lean Mahjong/WaitCompletionFinder.lean
```

## Python Classification Example

`examples/irreducible_wait_classifier.py` is a standard-library-only sample for
external consumers. It accepts a 4-, 7-, 10-, or 13-tile hand as distinct Tenhou
136 IDs, computes `waitDecompositionCodes`, removes complete melds while preserving
the exact wait-core set, and returns a stable global integer classification ID.
Red-five identity is ignored because every physical ID is normalized with `id // 4`.

```python
from irreducible_wait_classifier import classify_irreducible_wait

classification_id = classify_irreducible_wait([0, 4, 5, 8])  # 1223m -> 5
```

Run it with `examples` on the module search path. Non-tenpai and invalid hands raise
subclasses of `WaitClassificationError`.

```bash
PYTHONPATH=examples python3 -m unittest discover -s examples -p 'test_*.py'
```

## Documentation

Reader-facing guides:

- [docs/introduction.md](docs/introduction.md): Japanese introduction to Lean4 and proof-carrying programs for this project.
- [docs/reading-order.md](docs/reading-order.md): linear reading path for readers new to Lean.
- [docs/lean-vocabulary.md](docs/lean-vocabulary.md): recurring Lean syntax and proof vocabulary.
- [docs/domain-vocabulary.md](docs/domain-vocabulary.md): project-specific Mahjong terminology.

Writer and maintenance notes:

- [docs/documentation-policy.md](docs/documentation-policy.md): division between reader-facing guides, vocabulary pages, and maintenance notes.
- [docs/proof-comment-policy.md](docs/proof-comment-policy.md): division of responsibility between source comments and guides.
- [docs/review-backlog.md](docs/review-backlog.md): design and naming questions discovered during documentation.
- [docs/wait-decomposition-classification-key-2026-09-13.md](docs/wait-decomposition-classification-key-2026-09-13.md): Japanese design note for fitting wait-decomposition classifications into 64-bit keys.
- [docs/remote-compute-gcp-batch.md](docs/remote-compute-gcp-batch.md): Japanese operating plan for remote computation with GCP Batch and Spot VMs.
- [docs/remote-compute-platform-rationale-2026-10-09.md](docs/remote-compute-platform-rationale-2026-10-09.md):
  Japanese rationale for trialing GCP Batch and Spot VMs, including alternatives and review triggers.
- [Mahjong/README.md](Mahjong/README.md): module-level overview.

## Origin

This repository began as a fork of
[chantakan/lean4-devcontainer-template](https://github.com/chantakan/lean4-devcontainer-template)
for learning Lean 4. Its commit history preserves that origin; the repository has since become an
independent Mahjong formalization and computational research project.
