#!/usr/bin/env python3
"""
Validate that a bot PR diff is safe to automerge.

What it does:
  Checks PR file patches: only Dockerfile_v*.x may change.
  - modified: only alpine FROM and/or kubectl URL version lines
  - added: content must match existing Dockerfile template (only kubectl version differs)
    and kubectl version must match the minor in the filename

Input:
  Env FILES_JSON — JSON array from GET /repos/{owner}/{repo}/pulls/{n}/files
  CWD — repository root with existing Dockerfile_v*.x (for template compare)

Output:
  Stdout — one line:
    OK kubectl=<vX.Y.Z|vA,vB|none> alpine=<yes|no>
    or REJECT:<reason>
  Exit 0 always (caller decides based on OK/REJECT prefix)
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

ALPINE_RE = re.compile(r"^[-+]FROM docker\.io/alpine:\d+\.\d+\.\d+\s*$")
KUBECTL_RE = re.compile(
    r"^[-+].*https://dl\.k8s\.io/release/v\d+\.\d+\.\d+/bin/linux/amd64/kubectl.*$"
)
KUBECTL_PLUS = re.compile(
    r"^\+.*https://dl\.k8s\.io/release/(v\d+\.\d+\.\d+)/bin/linux/amd64/kubectl"
)
KUBECTL_IN_FILE = re.compile(
    r"https://dl\.k8s\.io/release/(v\d+\.\d+\.\d+)/bin/linux/amd64/kubectl"
)
DOCKERFILE_RE = re.compile(r"^Dockerfile_v(\d+)\.(\d+)\.x$")


def normalize(text: str) -> str:
    text = re.sub(
        r"FROM docker\.io/alpine:\d+\.\d+\.\d+",
        "FROM docker.io/alpine:__ALPINE__",
        text,
    )
    text = re.sub(
        r"https://dl\.k8s\.io/release/v\d+\.\d+\.\d+/bin/linux/amd64/kubectl",
        "https://dl.k8s.io/release/v__KUBECTL__/bin/linux/amd64/kubectl",
        text,
    )
    return text


def content_from_added_patch(patch: str) -> str:
    lines = []
    for line in patch.splitlines():
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+"):
            lines.append(line[1:])
        elif line.startswith("-"):
            raise ValueError("unexpected deleted line in added file patch")
        elif line.startswith(" "):
            lines.append(line[1:])
    body = "\n".join(lines)
    if body and not body.endswith("\n"):
        body += "\n"
    return body


def load_reference_normalized() -> str:
    refs = sorted(Path(".").glob("Dockerfile_v*.x"))
    if not refs:
        raise SystemExit("REJECT:no-reference-dockerfile")
    return normalize(refs[-1].read_text())


def main() -> int:
    files = json.loads(os.environ["FILES_JSON"])
    if not files:
        print("REJECT:no-files")
        return 0

    kubectl_versions: list[str] = []
    alpine_changed = False
    ref_norm = None

    for f in files:
        name = f.get("filename", "")
        status = f.get("status", "")
        patch = f.get("patch") or ""

        if status in ("removed", "renamed"):
            print(f"REJECT:status:{name}:{status}")
            return 0
        if not DOCKERFILE_RE.match(name):
            print(f"REJECT:file:{name}")
            return 0
        if not patch:
            print(f"REJECT:empty-patch:{name}")
            return 0

        if status == "added":
            m = DOCKERFILE_RE.match(name)
            assert m is not None
            major, minor = m.group(1), m.group(2)
            try:
                content = content_from_added_patch(patch)
            except ValueError as exc:
                print(f"REJECT:added-patch:{name}:{exc}")
                return 0

            km = KUBECTL_IN_FILE.search(content)
            if not km:
                print(f"REJECT:added-no-kubectl:{name}")
                return 0
            version = km.group(1)
            if not version.startswith(f"v{major}.{minor}."):
                print(f"REJECT:added-version-mismatch:{name}:{version}")
                return 0

            if ref_norm is None:
                ref_norm = load_reference_normalized()
            if normalize(content) != ref_norm:
                print(f"REJECT:added-template-mismatch:{name}")
                return 0

            kubectl_versions.append(version)
            continue

        for line in patch.splitlines():
            if not (line.startswith("+") or line.startswith("-")):
                continue
            if line.startswith("+++") or line.startswith("---"):
                continue
            if ALPINE_RE.match(line):
                if line.startswith("+"):
                    alpine_changed = True
                continue
            if KUBECTL_RE.match(line):
                m = KUBECTL_PLUS.match(line)
                if m:
                    kubectl_versions.append(m.group(1))
                continue
            print(f"REJECT:line:{name}:{line}")
            return 0

    unique: list[str] = []
    for v in kubectl_versions:
        if v not in unique:
            unique.append(v)

    kubectl = ",".join(unique) if unique else "none"
    alpine = "yes" if alpine_changed else "no"
    print(f"OK kubectl={kubectl} alpine={alpine}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
