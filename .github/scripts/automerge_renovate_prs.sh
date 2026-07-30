#!/usr/bin/env bash
#
# Validate and automerge eligible bot PRs.
#
# What it does:
#   Lists open github-actions[bot] PRs on renovate/* or chore/new-kubectl-minor-*,
#   validates each PR diff, merges safe ones with gh pr merge.
#
# Input (env):
#   REPO      — owner/name (e.g. identw/kubectl)
#   GH_TOKEN  — GitHub token with pull-requests:write + contents:write
#
# Output:
#   Stdout lines:
#     MERGED <pr> kubectl=<ver|none> alpine=<yes|no>   — successfully merged
#     PR #<n>: skip (...)                              — rejected / not merged
#   Exit 0 (partial merge failures are logged and skipped)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO="${REPO:?REPO is required}"
GH_TOKEN="${GH_TOKEN:?GH_TOKEN is required}"
export GH_TOKEN

pr_list="$(gh api "repos/${REPO}/pulls?state=open&per_page=100" --paginate)"
pr_numbers="$(PR_LIST_JSON="$pr_list" python3 "${SCRIPT_DIR}/list_eligible_bot_prs.py")"

if [ -z "${pr_numbers}" ]; then
  echo "No eligible bot PRs"
  exit 0
fi

while IFS= read -r PR_NUMBER; do
  [ -n "${PR_NUMBER}" ] || continue
  files_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" --paginate)"
  result="$(FILES_JSON="$files_json" python3 "${SCRIPT_DIR}/validate_bot_pr_diff.py")"

  if [[ "${result}" != OK* ]]; then
    echo "PR #${PR_NUMBER}: skip (${result})"
    continue
  fi

  echo "PR #${PR_NUMBER}: ${result} - merging"
  if ! gh pr merge "${PR_NUMBER}" --repo "${REPO}" --merge --delete-branch; then
    echo "PR #${PR_NUMBER}: merge failed (checks pending?)"
    continue
  fi

  echo "MERGED ${PR_NUMBER} ${result#OK }"
done <<< "${pr_numbers}"
