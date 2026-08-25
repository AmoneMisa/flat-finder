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

echo "Deploying flat-finder application images with tag: ${IMAGE_TAG}"

APP_SERVICES=(
  flat-finder-backend
  flat-finder-worker
  flat-finder-olx-fetcher
  flat-finder-olx-fetcher-ua
  flat-finder-social-fetcher
)

docker compose pull "${APP_SERVICES[@]}"

# Bring up stateless/core dependencies that are safe to reconcile on every
# deploy. Elasticsearch is handled separately below so a normal application
# commit cannot restart the stateful search node and trigger a long recovery.
docker compose up -d \
  flat-finder-postgres \
  flat-finder-olx-fetcher \
  flat-finder-olx-fetcher-ua \
  flat-finder-social-fetcher \
  flat-finder-olx-router

ES_CONTAINER_ID="$(docker compose ps -q flat-finder-elasticsearch 2>/dev/null || true)"

if [[ "$UPDATE_ELASTICSEARCH" == "true" ]]; then
  echo "Elasticsearch image changed; updating it to tag: ${IMAGE_TAG}"
  docker compose pull flat-finder-elasticsearch
  docker compose up -d flat-finder-elasticsearch
elif [[ -z "$ES_CONTAINER_ID" ]]; then
  echo "No Elasticsearch container exists; starting the latest published image"
  IMAGE_TAG=latest docker compose pull flat-finder-elasticsearch
  IMAGE_TAG=latest docker compose up -d flat-finder-elasticsearch
else
  echo "Keeping the existing Elasticsearch container unchanged"
fi

wait_for_healthy() {
  local service="$1" deadline=$((SECONDS + ${2:-120})) cid status
  while [[ $SECONDS -lt $deadline ]]; do
    cid="$(docker compose ps -q "$service" 2>/dev/null || true)"
    if [[ -n "$cid" ]]; then
      status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || true)"
      if [[ "$status" == "healthy" || "$status" == "none" ]]; then
        return 0
      fi
    fi
    sleep 3
  done
  echo "ERROR: ${service} did not become healthy in time."
  docker compose ps "$service" || true
  docker compose logs --tail=200 "$service" || true
  return 1
}

wait_for_healthy flat-finder-postgres 120
wait_for_healthy flat-finder-olx-fetcher 90
wait_for_healthy flat-finder-olx-fetcher-ua 90
wait_for_healthy flat-finder-social-fetcher 90

# Apply versioned PostgreSQL migrations before either application process starts.
# The runner takes a PostgreSQL advisory lock, so retries or overlapping deploys
# cannot apply the same migration concurrently.
docker compose run --rm --no-deps flat-finder-backend node src/migrate.js

# The API and direct worker both tolerate Elasticsearch being temporarily
# unavailable. --no-deps prevents an unhealthy search node from blocking an
# otherwise healthy application deployment.
docker compose up -d --no-deps \
  flat-finder-backend \
  flat-finder-worker

# A successful container start is not enough: module import errors and startup
# failures can put the API into a restart loop before port 4000 is ever opened.
wait_for_healthy flat-finder-backend 120

curl --fail --silent --show-error --max-time 10 \
  http://127.0.0.1:4000/health >/dev/null

# Smoke-test the actual listing route as well. This only requires the endpoint
# to respond successfully; it does not require any listing to exist.
curl --fail --silent --show-error --max-time 20 \
  'http://127.0.0.1:4000/api/listings?limit=1' >/dev/null

# Remove the retired queue-task-api and Python HTTP worker containers, together
# with any other services no longer present in Compose.
docker compose up -d --remove-orphans --no-deps \
  flat-finder-backend \
  flat-finder-worker \
  flat-finder-olx-fetcher \
  flat-finder-olx-fetcher-ua \
  flat-finder-social-fetcher \
  flat-finder-olx-router \
  flat-finder-postgres

docker image prune -af --filter "until=336h"

docker compose ps

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
