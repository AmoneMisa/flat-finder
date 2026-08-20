#!/usr/bin/env bash
# Standalone deploy for the flat-finder stack. Images are built in GitHub Actions
# and pulled from GHCR; the production server never builds application images.
set -euo pipefail

cd "$(dirname "$0")"

IMAGE_TAG="${1:-${IMAGE_TAG:-latest}}"
export IMAGE_TAG

# GHCR packages are private by default, and `docker compose pull` is fatal under
# set -e. Log in when credentials are supplied; skip when the daemon already
# holds a login from a previous manual `docker login ghcr.io`.
if [ -n "${GHCR_USER:-}" ] && [ -n "${GHCR_TOKEN:-}" ]; then
  printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
fi

# Deploy the compose definition from the revision the images were built from.
# Tracking master instead pairs this run's images with whatever HEAD happens to
# be, which drifts as soon as two deploys overlap.
if [ -d .git ]; then
  git fetch --prune origin
  if git rev-parse --verify --quiet "${IMAGE_TAG}^{commit}" >/dev/null; then
    git checkout --detach "$IMAGE_TAG"
  else
    # Manual run with a floating tag (e.g. `latest`): track master instead.
    git checkout master
    git pull --ff-only
  fi
fi

echo "Deploying flat-finder images with tag: ${IMAGE_TAG}"
docker compose pull
docker compose up -d --remove-orphans

# Reclaim superseded images. Plain `image prune -f` drops only dangling layers,
# and every build keeps its :<sha> tag, so it never collected anything. Images
# still attached to a container (running or stopped) are always preserved.
docker image prune -af --filter "until=336h"

docker compose ps
