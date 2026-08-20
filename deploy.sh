#!/usr/bin/env bash
# Standalone deploy for the flat-finder stack. Application images are built in
# GitHub Actions and pulled from GHCR; the production server never builds them.
# Elasticsearch is intentionally treated as stateful infrastructure: ordinary
# application deploys leave its running container untouched.
set -euo pipefail

cd "$(dirname "$0")"

IMAGE_TAG="${1:-${IMAGE_TAG:-latest}}"
UPDATE_ELASTICSEARCH="${2:-false}"
export IMAGE_TAG

if [[ "$UPDATE_ELASTICSEARCH" != "true" ]]; then
  UPDATE_ELASTICSEARCH="false"
fi

# Pull the compose/deploy definition matching the pushed revision.
if [ -d .git ]; then
  git pull --ff-only
fi

echo "Deploying flat-finder application images with tag: ${IMAGE_TAG}"

APP_SERVICES=(
  flat-finder-backend
  flat-finder-queue-task-api
  flat-finder-queue-dispatcher
  flat-finder-queue-worker-1
  flat-finder-queue-worker-2
  flat-finder-olx-fetcher
  flat-finder-olx-fetcher-ua
)

docker compose pull "${APP_SERVICES[@]}"

# Bring up stateless/core dependencies that are safe to reconcile on every
# deploy. Elasticsearch is handled separately below so a normal application
# commit cannot restart the stateful search node and trigger a long recovery.
docker compose up -d \
  flat-finder-redis \
  flat-finder-postgres \
  flat-finder-rabbitmq \
  flat-finder-olx-fetcher \
  flat-finder-olx-fetcher-ua \
  flat-finder-olx-router

ES_CONTAINER_ID="$(docker compose ps -q flat-finder-elasticsearch 2>/dev/null || true)"

if [[ "$UPDATE_ELASTICSEARCH" == "true" ]]; then
  echo "Elasticsearch image changed; updating it to tag: ${IMAGE_TAG}"
  docker compose pull flat-finder-elasticsearch
  docker compose up -d flat-finder-elasticsearch
elif [[ -z "$ES_CONTAINER_ID" ]]; then
  # First deployment / manually removed container. Use the last published ES
  # image instead of assuming this application SHA has an ES image.
  echo "No Elasticsearch container exists; starting the latest published image"
  IMAGE_TAG=latest docker compose pull flat-finder-elasticsearch
  IMAGE_TAG=latest docker compose up -d flat-finder-elasticsearch
else
  echo "Keeping the existing Elasticsearch container unchanged"
fi

# Both Node services already degrade gracefully when Elasticsearch is
# unavailable. --no-deps is deliberate: an unhealthy search node must not block
# deployment of the API or queue task API.
docker compose up -d --no-deps \
  flat-finder-backend \
  flat-finder-queue-task-api

docker compose up -d --no-deps \
  flat-finder-queue-dispatcher \
  flat-finder-queue-worker-1 \
  flat-finder-queue-worker-2

docker image prune -f

docker compose ps

# Do not fail the whole deploy solely because Elasticsearch is unhealthy. Print
# enough diagnostics into the Actions log to make the underlying ES problem
# visible and actionable on the next pass.
ES_CONTAINER_ID="$(docker compose ps -q flat-finder-elasticsearch 2>/dev/null || true)"
if [[ -n "$ES_CONTAINER_ID" ]]; then
  ES_HEALTH="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$ES_CONTAINER_ID" 2>/dev/null || true)"
  if [[ "$ES_HEALTH" == "unhealthy" ]]; then
    echo "WARNING: Elasticsearch is unhealthy; application deployment remains online in degraded-search mode."
    echo "Last Elasticsearch logs:"
    docker compose logs --tail=150 flat-finder-elasticsearch || true
  elif [[ "$ES_HEALTH" == "starting" ]]; then
    echo "Elasticsearch is still starting; application deployment continues in degraded-search mode until it becomes healthy."
  fi
fi
