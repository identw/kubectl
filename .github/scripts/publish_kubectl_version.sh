#!/usr/bin/env bash
# Create git tag + GitHub release for a kubectl version, publish image, refresh README.
# Usage: publish_kubectl_version.sh <vX.Y.Z>
set -euo pipefail

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

.github/scripts/docker_publish.sh "${DOCKERFILE}" "${VERSION}"

python3 .github/scripts/update_readme.py
if [ -n "$(git status --porcelain README.md)" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git pull --rebase origin master
  git add README.md
  git commit -m "docs: update image table for ${VERSION}"
  git push origin HEAD:master
  echo "Pushed README update"
fi
