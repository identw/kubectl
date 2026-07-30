#!/usr/bin/env bash
#
# After a merged PR: tag/release/publish any new kubectl versions found in the PR diff.
#
# What it does:
#   Fetches PR files via API, extracts kubectl versions from Dockerfile_v*.x patches,
#   runs publish_kubectl_version.sh for each, then publishes :latest.
#
# Input (env):
#   PR_NUMBER — pull request number
#   REPO      — owner/name
#   GH_TOKEN / GITHUB_TOKEN, IMAGE, DOCKER_*, GITHUB_USER — for publish helpers
#   CWD — repo root on main
#
# Output:
#   Side effects — tags, releases, image pushes, README update
#   Exit 0 if no kubectl versions in diff; non-zero on publish failure
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PR_NUMBER="${PR_NUMBER:?PR_NUMBER is required}"
REPO="${REPO:?REPO is required}"
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:?GITHUB_TOKEN/GH_TOKEN required}}"
export GH_TOKEN

files_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" --paginate)"
VERSIONS="$(FILES_JSON="$files_json" python3 "${SCRIPT_DIR}/extract_kubectl_versions_from_pr_files.py")"

if [ -z "${VERSIONS}" ]; then
  echo "No kubectl version additions in Dockerfile_v*.x; skipping tag/release"
  exit 0
fi

while IFS= read -r VERSION; do
  [ -n "${VERSION}" ] || continue
  "${SCRIPT_DIR}/publish_kubectl_version.sh" "${VERSION}"
done <<< "${VERSIONS}"

dockerfile="$("${SCRIPT_DIR}/resolve_latest_dockerfile.sh")"
"${SCRIPT_DIR}/docker_publish.sh" "${dockerfile}" "latest"
