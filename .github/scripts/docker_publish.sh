#!/usr/bin/env bash
# Build and push image for a specific Dockerfile and tag name.
set -euo pipefail

DOCKERFILE="${1:?Dockerfile path required}"
IMAGE_TAG="${2:?image tag required}"
IMAGE="${IMAGE:?IMAGE is required}"
DOCKER_USER="${DOCKER_USER:?}"
DOCKER_PASSWORD="${DOCKER_PASSWORD:?}"
GITHUB_USER="${GITHUB_USER:?}"
GITHUB_TOKEN="${GITHUB_TOKEN:?}"

docker build -f "${DOCKERFILE}" -t "docker.io/${IMAGE}:${IMAGE_TAG}" .
docker tag "docker.io/${IMAGE}:${IMAGE_TAG}" "ghcr.io/${IMAGE}:${IMAGE_TAG}"
docker login -u "${DOCKER_USER}" -p "${DOCKER_PASSWORD}"
docker push "docker.io/${IMAGE}:${IMAGE_TAG}"
docker login -u "${GITHUB_USER}" -p "${GITHUB_TOKEN}" ghcr.io
docker push "ghcr.io/${IMAGE}:${IMAGE_TAG}"
