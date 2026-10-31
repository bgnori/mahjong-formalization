#!/usr/bin/env python3

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
REPORT_PATHS = (
    Path("reports/four-tile-direct-report.json"),
    Path("reports/seven-tile-report.json"),
    Path("reports/ten-tile-report.json"),
    Path("reports/thirteen-tile-report.json"),
)
CLASSIFIER_FILES = ("index.html", "app.js", "classifier.js", "classification-table.js")


def result_revision(path: Path, repository: str) -> dict[str, str]:
    result = subprocess.run(
        ["git", "log", "-1", "--format=%H%n%cI", "--", path.as_posix()],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    lines = result.stdout.strip().splitlines()
    if len(lines) != 2:
        raise RuntimeError(f"Could not determine the Git revision for {path}")
    commit, committed_at = lines
    return {
        "commit": commit,
        "committedAt": committed_at,
        "sourcePath": path.as_posix(),
        "commitUrl": f"https://github.com/{repository}/commit/{commit}",
    }


def write_report(source: Path, destination: Path, revision: dict[str, str]) -> None:
    data = json.loads(source.read_text(encoding="utf-8"))
    data["resultRevision"] = revision
    destination.write_text(
        json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def build(output: Path, repository: str) -> None:
    output.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "reports/report-viewer.html", output / "index.html")
    for path in REPORT_PATHS:
        write_report(
            ROOT / path,
            output / path.name,
            result_revision(path, repository),
        )
    classifier = output / "classifier"
    classifier.mkdir(exist_ok=True)
    for name in CLASSIFIER_FILES:
        shutil.copy2(ROOT / "web" / name, classifier / name)
    (output / ".nojekyll").touch()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Assemble the static computation-report site for GitHub Pages."
    )
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    repository = os.environ.get("GITHUB_REPOSITORY", "bgnori/mahjong-formalization")
    build(args.output, repository)


if __name__ == "__main__":
    main()
