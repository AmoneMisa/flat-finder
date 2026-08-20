#!/usr/bin/env bash
# Standalone deploy for the flat-finder stack. Images are built in GitHub Actions
# and pulled from GHCR; the production server never builds application images.
set -euo pipefail

cd "$(dirname "$0")"

IMAGE_TAG="${1:-${IMAGE_TAG:-latest}}"
export IMAGE_TAG

# Pull the compose/deploy definition matching the pushed revision.
if [ -d .git ]; then
  git pull --ff-only
fi

echo "Deploying flat-finder images with tag: ${IMAGE_TAG}"
docker compose pull
docker compose up -d --remove-orphans
docker image prune -f
docker compose ps
