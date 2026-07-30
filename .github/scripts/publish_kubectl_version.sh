#!/usr/bin/env bash
#
# Publish one kubectl patch version: git tag, GitHub Release, image, README table.
#
# What it does:
#   Ensures tag vX.Y.Z exists, creates GitHub release if missing, builds/pushes
#   the image from Dockerfile_vX.Y.x, regenerates README version table and may
#   commit/push it to main.
#
# Input:
#   Arg1 — version (e.g. v1.36.3)
#   Env:
#     IMAGE — docker image name (owner/repo)
#     REPO  — GitHub repo (defaults to IMAGE)
#     GH_TOKEN or GITHUB_TOKEN
#     DOCKER_USER, DOCKER_PASSWORD, GITHUB_USER, GITHUB_TOKEN — for docker_publish.sh
#   CWD — repository root with Dockerfile_v*.x
#
# Output:
#   Side effects — tag, release, registry push, optional README commit on main
#   Exit non-zero if Dockerfile missing or publish fails
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERSION="${1:?kubectl version required, e.g. v1.36.3}"
IMAGE="${IMAGE:?IMAGE is required}"
REPO="${REPO:-$IMAGE}"
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:?GITHUB_TOKEN/GH_TOKEN required}}"
export GH_TOKEN

MINOR="$(echo "${VERSION}" | sed -E 's/^(v[0-9]+\.[0-9]+)\.[0-9]+$/\1/')"
DOCKERFILE="Dockerfile_${MINOR}.x"

if [ ! -f "${DOCKERFILE}" ]; then
  echo "Missing ${DOCKERFILE} for ${VERSION}" >&2
  exit 1
fi

if git rev-parse "${VERSION}" >/dev/null 2>&1; then
  echo "Tag ${VERSION} already exists"
else
  git tag "${VERSION}"
  git push origin "${VERSION}"
  echo "Created tag ${VERSION}"
fi

if gh release view "${VERSION}" --repo "${REPO}" >/dev/null 2>&1; then
  echo "Release ${VERSION} already exists"
else
  gh release create "${VERSION}" \
    --repo "${REPO}" \
    --title "${VERSION}" \
    --notes "$(cat <<EOF
kubectl ${VERSION}

\`\`\`
docker pull ghcr.io/${IMAGE}:${VERSION}
\`\`\`

Also available as \`docker.io/${IMAGE}:${VERSION}\`.
EOF
)"
  echo "Created release ${VERSION}"
fi

"${SCRIPT_DIR}/docker_publish.sh" "${DOCKERFILE}" "${VERSION}"

python3 "${SCRIPT_DIR}/update_readme.py"
if [ -n "$(git status --porcelain README.md)" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git pull --rebase origin main
  git add README.md
  git commit -m "docs: update image table for ${VERSION}"
  git push origin HEAD:main
  echo "Pushed README update"
fi
