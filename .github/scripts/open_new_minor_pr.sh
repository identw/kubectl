#!/usr/bin/env bash
#
# Detect missing kubectl minors, commit Dockerfiles, open a PR.
#
# What it does:
#   Runs detect_new_kubectl_minors.py; if new files exist, pushes a branch and
#   opens a PR (eligible for automerge). Sets created_pr in GITHUB_OUTPUT when present.
#
# Input (env):
#   GH_TOKEN — GitHub token (contents + pull-requests write)
#   REPO     — owner/name
#   GITHUB_OUTPUT — optional; written by Actions
#   CWD — repo root on default branch
#
# Output:
#   Side effects — new Dockerfile_v*.x, remote branch, open PR
#   GITHUB_OUTPUT created_pr=true|false
#   Exit 0
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO="${REPO:?REPO is required}"
GH_TOKEN="${GH_TOKEN:?GH_TOKEN is required}"
export GH_TOKEN

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "created_pr=false" >> "${GITHUB_OUTPUT}"
fi

result_json="$(python3 "${SCRIPT_DIR}/detect_new_kubectl_minors.py")"
has_changes="$(RESULT_JSON="$result_json" python3 -c 'import json,os; print("yes" if json.loads(os.environ["RESULT_JSON"]).get("has_changes") else "no")')"

if [ "${has_changes}" != "yes" ]; then
  echo "No new kubectl minor versions to add"
  exit 0
fi

NEW_FILES="$(RESULT_JSON="$result_json" python3 -c 'import json,os; print(" ".join(json.loads(os.environ["RESULT_JSON"])["files"]))')"
SUMMARY="$(RESULT_JSON="$result_json" python3 -c 'import json,os; print(json.loads(os.environ["RESULT_JSON"])["summary"])')"

BRANCH="chore/new-kubectl-minor-$(date +%Y%m%d%H%M%S)"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout -b "${BRANCH}"
# shellcheck disable=SC2086
git add ${NEW_FILES}
git commit -m "Add Dockerfiles for new kubectl minor versions"

git push -u origin "${BRANCH}"

gh pr create \
  --repo "${REPO}" \
  --title "Add Dockerfiles for new kubectl minor versions" \
  --body "$(cat <<EOF
## Summary
New kubectl minor release(s) detected. Added:
- ${SUMMARY}

Eligible for automerge when the new Dockerfile(s) match the existing template
(only kubectl version differs). After merge: tag, GitHub release, image publish,
and README table update.
EOF
)"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "created_pr=true" >> "${GITHUB_OUTPUT}"
fi
