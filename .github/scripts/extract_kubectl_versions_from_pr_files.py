#!/usr/bin/env python3
"""
Extract new kubectl versions from a PR files JSON (patches).

What it does:
  Scans added/changed lines in Dockerfile_v*.x patches for
  https://dl.k8s.io/release/vX.Y.Z/... kubectl URLs.

Input:
  Env FILES_JSON — JSON array from GET /repos/{owner}/{repo}/pulls/{n}/files
  (or pass the JSON as the first CLI argument)

Output:
  Stdout — unique versions one per line, sorted by semver (e.g. v1.36.3)
  Empty stdout if none found
  Exit 0
"""
from __future__ import annotations

import json
import os
import re
import sys

KUBECTL_PLUS = re.compile(
    r"^\+.*https://dl\.k8s\.io/release/(v\d+\.\d+\.\d+)/bin/linux/amd64/kubectl"
)
DOCKERFILE_RE = re.compile(r"^Dockerfile_v\d+\.\d+\.x$")


def main() -> int:
    if "FILES_JSON" in os.environ:
        raw = os.environ["FILES_JSON"]
    elif len(sys.argv) > 1:
        raw = sys.argv[1]
    else:
        raw = sys.stdin.read()

    files = json.loads(raw)
    versions: list[str] = []
    for f in files:
        name = f.get("filename", "")
        if not DOCKERFILE_RE.match(name):
            continue
        patch = f.get("patch") or ""
        for line in patch.splitlines():
            m = KUBECTL_PLUS.match(line)
            if m:
                versions.append(m.group(1))

    for v in sorted(set(versions), key=lambda s: list(map(int, s[1:].split(".")))):
        print(v)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
