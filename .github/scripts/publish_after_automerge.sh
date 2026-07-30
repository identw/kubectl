#!/usr/bin/env bash
#
# After automerge: create tags/releases, publish images, refresh README/latest.
#
# What it does:
#   Reads MERGED lines from automerge_renovate_prs.sh, for each kubectl version
#   runs publish_kubectl_version.sh; may rebuild :latest.
#
# Input:
#   Arg1 (optional) — path to file with MERGED lines (default: /tmp/merged.txt)
#   Env:
#     IMAGE, REPO, GH_TOKEN/GITHUB_TOKEN, DOCKER_USER, DOCKER_PASSWORD,
#     GITHUB_USER, GITHUB_TOKEN — as required by publish_kubectl_version.sh / docker_publish.sh
#   CWD — repo root on main (already pulled)
#
# Output:
#   Side effects — git tags, GitHub releases, registry pushes, possible README commit
#   Exit non-zero on publish failure
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MERGED_FILE="${1:-/tmp/merged.txt}"

if [ ! -s "${MERGED_FILE}" ]; then
  echo "No MERGED lines in ${MERGED_FILE}"
  exit 0
fi

publish_latest=false

while read -r _ pr rest; do
  kubectl="$(echo "${rest}" | sed -n 's/.*kubectl=\([^ ]*\).*/\1/p')"
  alpine="$(echo "${rest}" | sed -n 's/.*alpine=\([^ ]*\).*/\1/p')"

  if [ "${alpine}" = "yes" ]; then
    publish_latest=true
  fi

  if [ "${kubectl}" != "none" ] && [ -n "${kubectl}" ]; then
    IFS=',' read -ra versions <<< "${kubectl}"
    for version in "${versions[@]}"; do
      "${SCRIPT_DIR}/publish_kubectl_version.sh" "${version}"
    done
    publish_latest=true
  fi
done < "${MERGED_FILE}"

if [ "${publish_latest}" = "true" ]; then
  dockerfile="$("${SCRIPT_DIR}/resolve_latest_dockerfile.sh")"
  "${SCRIPT_DIR}/docker_publish.sh" "${dockerfile}" "latest"
fi
