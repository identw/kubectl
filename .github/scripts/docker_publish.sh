#!/usr/bin/env bash
#
# Build and push a kubectl image to Docker Hub and GHCR.
#
# What it does:
#   docker build -f <Dockerfile> and push docker.io/$IMAGE:<tag> + ghcr.io/$IMAGE:<tag>
#
# Input:
#   Arg1 — Dockerfile path (e.g. Dockerfile_v1.36.x)
#   Arg2 — image tag (e.g. v1.36.3 or latest)
#   Env:
#     IMAGE          — repository image name (e.g. identw/kubectl)
#     DOCKER_USER, DOCKER_PASSWORD — Docker Hub
#     GITHUB_USER, GITHUB_TOKEN    — GHCR login
#
# Output:
#   Side effects — image published to both registries
#   Exit non-zero on docker failure
#
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
