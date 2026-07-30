#!/usr/bin/env python3
"""
Detect missing kubectl minor lines and create Dockerfile_v*.x files.

What it does:
  Fetches kubernetes/kubernetes GitHub releases, finds stable v1.25+ minors
  that have no Dockerfile_vMAJOR.MINOR.x yet, and writes them using alpine
  from the newest existing Dockerfile.

Input:
  Env GH_TOKEN — GitHub token for API access
  CWD — repository root with Dockerfile_v*.x

Output:
  Stdout — JSON object:
    {"has_changes": false}
    or {"has_changes": true, "files": ["Dockerfile_v1.37.x", ...], "summary": "..."}
  Side effect — creates new Dockerfile_v*.x on disk when has_changes is true
  Exit 0
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(".")
DOCKERFILE_RE = re.compile(r"^Dockerfile_v(\d+)\.(\d+)\.x$")


def http_get(url: str):
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "identw-kubectl-new-minor",
            "Authorization": f"Bearer {os.environ['GH_TOKEN']}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def existing_minors():
    out = {}
    for path in ROOT.glob("Dockerfile_v*.x"):
        m = DOCKERFILE_RE.match(path.name)
        if not m:
            continue
        out[(int(m.group(1)), int(m.group(2)))] = path
    return out


def latest_alpine(existing):
    if not existing:
        return "3.24.1"
    newest = max(existing)
    text = existing[newest].read_text()
    m = re.search(r"FROM docker\.io/alpine:(\d+\.\d+\.\d+)", text)
    if not m:
        raise SystemExit(f"Cannot parse alpine from {existing[newest]}")
    return m.group(1)


def dockerfile_body(alpine: str, kubectl: str) -> str:
    return (
        f"FROM docker.io/alpine:{alpine}\n"
        f"LABEL org.opencontainers.image.source https://github.com/identw/kubectl\n"
        f"\n"
        f"RUN apk add --no-cache curl bash \\\n"
        f"    && curl -L https://dl.k8s.io/release/v{kubectl}/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl \\\n"
        f"    && chmod +x /usr/local/bin/kubectl\n"
    )


def main() -> int:
    releases = []
    for page in range(1, 6):
        batch = http_get(
            f"https://api.github.com/repos/kubernetes/kubernetes/releases?per_page=100&page={page}"
        )
        if not batch:
            break
        releases.extend(batch)

    latest_by_minor = {}
    for rel in releases:
        if rel.get("prerelease") or rel.get("draft"):
            continue
        tag = rel.get("tag_name") or ""
        m = re.match(r"^v(\d+)\.(\d+)\.(\d+)$", tag)
        if not m:
            continue
        major, minor, patch = map(int, m.groups())
        if major != 1 or minor < 25:
            continue
        key = (major, minor)
        ver = (patch, tag[1:])
        if key not in latest_by_minor or ver > latest_by_minor[key]:
            latest_by_minor[key] = ver

    existing = existing_minors()
    missing = sorted(set(latest_by_minor) - set(existing))
    if not missing:
        print(json.dumps({"has_changes": False}))
        return 0

    alpine = latest_alpine(existing)
    created = []
    for key in missing:
        major, minor = key
        kubectl = latest_by_minor[key][1]
        name = f"Dockerfile_v{major}.{minor}.x"
        Path(name).write_text(dockerfile_body(alpine, kubectl))
        created.append((name, kubectl))
        print(f"Created {name} with kubectl v{kubectl}", file=sys.stderr)

    print(
        json.dumps(
            {
                "has_changes": True,
                "files": [n for n, _ in created],
                "summary": ", ".join(f"{n} (v{v})" for n, v in created),
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
