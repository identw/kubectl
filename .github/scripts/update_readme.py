#!/usr/bin/env python3
"""Regenerate README.md image table from Dockerfile_v*.x files."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCKERFILE_RE = re.compile(r"^Dockerfile_v(\d+)\.(\d+)\.x$")
KUBECTL_RE = re.compile(
    r"https://dl\.k8s\.io/release/(v\d+\.\d+\.\d+)/bin/linux/amd64/kubectl"
)

MARKER_START = "<!-- VERSION_TABLE:START -->"
MARKER_END = "<!-- VERSION_TABLE:END -->"

README_TEMPLATE = """# kubectl

Minimal [Alpine](https://hub.docker.com/_/alpine)-based Docker images with `kubectl`.

Images are published to:

- `ghcr.io/identw/kubectl`
- `docker.io/identw/kubectl`

`latest` tracks the newest minor line below.

## Available versions

{marker_start}
{table}
{marker_end}
"""


def collect_versions() -> list[tuple[str, str]]:
    rows: list[tuple[tuple[int, int], str, str]] = []
    for path in ROOT.glob("Dockerfile_v*.x"):
        m = DOCKERFILE_RE.match(path.name)
        if not m:
            continue
        major, minor = int(m.group(1)), int(m.group(2))
        text = path.read_text()
        km = KUBECTL_RE.search(text)
        if not km:
            raise SystemExit(f"kubectl version not found in {path.name}")
        patch_tag = km.group(1)
        rows.append(((major, minor), f"v{major}.{minor}.x", patch_tag))
    rows.sort(key=lambda r: r[0], reverse=True)
    return [(minor_label, patch_tag) for _, minor_label, patch_tag in rows]


def render_table(versions: list[tuple[str, str]]) -> str:
    lines = [
        "| Minor | Image |",
        "| --- | --- |",
    ]
    for minor_label, patch_tag in versions:
        lines.append(
            f"| {minor_label} | `ghcr.io/identw/kubectl:{patch_tag}` |"
        )
    return "\n".join(lines)


def replace_table(readme: str, table: str) -> str:
    if MARKER_START in readme and MARKER_END in readme:
        before, rest = readme.split(MARKER_START, 1)
        _, after = rest.split(MARKER_END, 1)
        return f"{before}{MARKER_START}\n{table}\n{MARKER_END}{after}"
    return README_TEMPLATE.format(
        marker_start=MARKER_START,
        marker_end=MARKER_END,
        table=table,
    )


def main() -> int:
    versions = collect_versions()
    if not versions:
        print("No Dockerfile_v*.x found", file=sys.stderr)
        return 1
    table = render_table(versions)
    readme_path = ROOT / "README.md"
    current = readme_path.read_text() if readme_path.exists() else ""
    updated = replace_table(current, table)
    if updated == current:
        print("README.md already up to date")
        return 0
    readme_path.write_text(updated if updated.endswith("\n") else updated + "\n")
    print("Updated README.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
