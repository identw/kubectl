#!/usr/bin/env python3
"""
List open PRs eligible for bot automerge.

What it does:
  Filters a GitHub pulls JSON payload for non-draft PRs from github-actions[bot]
  on renovate/* or chore/new-kubectl-minor-* branches.

Input:
  Env PR_LIST_JSON — JSON array from GET /repos/{owner}/{repo}/pulls

Output:
  Stdout — one PR number per line
  Exit 0 always (empty stdout means none eligible)
"""
from __future__ import annotations

import json
import os
import sys


def main() -> int:
    prs = json.loads(os.environ["PR_LIST_JSON"])
    for pr in prs:
        user = (pr.get("user") or {}).get("login") or ""
        head_ref = ((pr.get("head") or {}).get("ref") or "")
        draft = pr.get("draft", False)
        if user != "github-actions[bot]" or draft:
            continue
        if head_ref.startswith("renovate/") or head_ref.startswith(
            "chore/new-kubectl-minor-"
        ):
            print(pr["number"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
