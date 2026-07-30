#!/usr/bin/env bash
#
# Resolve the Dockerfile for the highest kubectl minor line in the repo.
#
# What it does:
#   Finds Dockerfile_v*.x and picks the greatest MAJOR.MINOR by numeric sort.
#
# Input:
#   CWD — repository root
#
# Output:
#   Stdout — path like Dockerfile_v1.36.x
#   Exit 1 if none found
#
set -euo pipefail

DOCKERFILE="$(ls -1 Dockerfile_v*.x 2>/dev/null | sed 's/^Dockerfile_v//' | sort -t. -k1,1n -k2,2n | tail -1 | sed 's/^/Dockerfile_v/' || true)"
if [ -z "${DOCKERFILE}" ] || [ ! -f "${DOCKERFILE}" ]; then
  echo "No Dockerfile_v*.x found" >&2
  exit 1
fi
echo "${DOCKERFILE}"
