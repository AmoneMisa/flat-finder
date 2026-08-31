#!/usr/bin/env bash
# Standalone deploy for the flat-finder stack. Application images are normally
# built in GitHub Actions and pulled from GHCR. LOCAL_BUILD=1 lets the guarded
# server-side fallback deploy images built directly on the production host.
set -euo pipefail

cd "$(dirname "$0")"

IMAGE_TAG="${1:-${IMAGE_TAG:-latest}}"
UPDATE_ELASTICSEARCH="${2:-false}"
DEPLOY_SHA="${DEPLOY_SHA:-$IMAGE_TAG}"
DEPLOY_SOURCE="${DEPLOY_SOURCE:-manual}"
LOCAL_BUILD="${LOCAL_BUILD:-0}"
FORCE_DEPLOY="${FORCE_DEPLOY:-0}"
STATE_DIR="${DEPLOY_STATE_DIR:-/var/lib/flat-finder-deploy}"
export IMAGE_TAG
mkdir -p "$STATE_DIR"

if [[ "$FORCE_DEPLOY" != "1" && -f "$STATE_DIR/deployed.sha" ]] &&
   [[ "$(cat "$STATE_DIR/deployed.sha")" == "$DEPLOY_SHA" ]]; then
  echo "Commit $DEPLOY_SHA is already deployed; skipping duplicate rollout."
  exit 0
fi

if [[ "$UPDATE_ELASTICSEARCH" != "true" ]]; then
  UPDATE_ELASTICSEARCH="false"
fi

echo "Deploying flat-finder application images with tag: ${IMAGE_TAG} (source=${DEPLOY_SOURCE})"

APP_SERVICES=(
  flat-finder-backend
  flat-finder-worker
  flat-finder-olx-fetcher
  flat-finder-olx-fetcher-ua
  flat-finder-social-fetcher
)

if [[ "$LOCAL_BUILD" == "1" ]]; then
  echo "Using locally built application images; registry pull skipped."
else
  docker compose pull "${APP_SERVICES[@]}"
fi

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
  if [[ "$LOCAL_BUILD" != "1" ]]; then
    docker compose pull flat-finder-elasticsearch
  fi
  docker compose up -d flat-finder-elasticsearch
elif [[ -z "$ES_CONTAINER_ID" ]]; then
  echo "No Elasticsearch container exists; starting the latest published image"
  if [[ "$LOCAL_BUILD" == "1" ]]; then
    docker compose up -d flat-finder-elasticsearch
  else
    IMAGE_TAG=latest docker compose pull flat-finder-elasticsearch
    IMAGE_TAG=latest docker compose up -d flat-finder-elasticsearch
  fi
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

wait_for_healthy flat-finder-backend 120

curl --fail --silent --show-error --max-time 10 \
  http://127.0.0.1:4000/health >/dev/null

# Cheap generic smoke test plus one realistic first-page UZ request. The latter
# guards against reintroducing synchronous per-listing enrichment that can leave
# nginx waiting for response headers until its upstream timeout expires.
curl --fail --silent --show-error --max-time 20 \
  'http://127.0.0.1:4000/api/listings?limit=1' >/dev/null

curl --fail --silent --show-error --max-time 15 \
  'http://127.0.0.1:4000/api/listings?countries=UZ&limit=20' >/dev/null

# Remove retired services and any other containers no longer present in Compose.
docker compose up -d --remove-orphans --no-deps \
  flat-finder-backend \
  flat-finder-worker \
  flat-finder-olx-fetcher \
  flat-finder-olx-fetcher-ua \
  flat-finder-social-fetcher \
  flat-finder-olx-router \
  flat-finder-postgres

verify_service_image() {
  local service="$1" image_repo="$2" expected_ref expected_id cid actual_ref actual_id
  expected_ref="${image_repo}:${IMAGE_TAG}"
  expected_id="$(docker image inspect "$expected_ref" --format '{{.Id}}' 2>/dev/null || true)"
  cid="$(docker compose ps -q "$service" 2>/dev/null || true)"
  if [[ -z "$cid" || -z "$expected_id" ]]; then
    echo "ERROR: cannot verify image for $service (expected $expected_ref)." >&2
    return 1
  fi
  actual_ref="$(docker inspect "$cid" --format '{{.Config.Image}}')"
  actual_id="$(docker inspect "$cid" --format '{{.Image}}')"
  if [[ "$actual_ref" != "$expected_ref" || "$actual_id" != "$expected_id" ]]; then
    echo "ERROR: $service is not running the expected immutable image." >&2
    echo "  expected ref: $expected_ref" >&2
    echo "  actual ref:   $actual_ref" >&2
    echo "  expected id:  $expected_id" >&2
    echo "  actual id:    $actual_id" >&2
    return 1
  fi
  echo "Verified $service -> $expected_ref ($actual_id)"
}

# Do not record a successful rollout unless every application container is
# provably running the exact immutable image tag for this deployment.
verify_service_image flat-finder-backend ghcr.io/amonemisa/flat-finder-backend
verify_service_image flat-finder-worker ghcr.io/amonemisa/flat-finder-backend
verify_service_image flat-finder-olx-fetcher ghcr.io/amonemisa/flat-finder-olx-fetcher
verify_service_image flat-finder-olx-fetcher-ua ghcr.io/amonemisa/flat-finder-olx-fetcher
verify_service_image flat-finder-social-fetcher ghcr.io/amonemisa/flat-finder-social-fetcher

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

# Record only a fully successful rollout. GitHub and local fallback both consult
# this marker, so a late hosted runner cannot deploy the same SHA twice.
printf '%s\n' "$DEPLOY_SHA" > "$STATE_DIR/deployed.sha.tmp"
mv "$STATE_DIR/deployed.sha.tmp" "$STATE_DIR/deployed.sha"
printf 'SHA=%s\nSOURCE=%s\nTIME=%s\n' \
  "$DEPLOY_SHA" "$DEPLOY_SOURCE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_DIR/deployed.meta"
echo "Recorded successful deployment: $DEPLOY_SHA ($DEPLOY_SOURCE)"
