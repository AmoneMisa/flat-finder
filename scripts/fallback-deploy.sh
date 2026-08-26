#!/usr/bin/env bash
# Build and deploy current master directly on the production host if the GitHub
# hosted workflow has not acquired a runner within the grace period. --force
# performs the same guarded local build immediately.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

REPO="AmoneMisa/flat-finder"
WORKFLOW_PATH=".github/workflows/deploy.yml"
THRESHOLD_SECONDS="${FALLBACK_THRESHOLD_SECONDS:-180}"
STATE_DIR="${DEPLOY_STATE_DIR:-/var/lib/flat-finder-deploy}"
LOCK_FILE="/tmp/flat-finder-deploy.lock"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1
mkdir -p "$STATE_DIR"

log() { printf '[flat-finder-fallback] %s\n' "$*"; }

refresh_remote() {
  git fetch --quiet origin master
  REMOTE_SHA="$(git rev-parse origin/master)"
  COMMIT_EPOCH="$(git show -s --format=%ct "$REMOTE_SHA")"
}

already_deployed() {
  [[ -f "$STATE_DIR/deployed.sha" ]] && [[ "$(cat "$STATE_DIR/deployed.sha")" == "$REMOTE_SHA" ]]
}

runner_state() {
  local tmp status_line
  tmp="$(mktemp)"
  if ! curl -fsS --max-time 15 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${REPO}/actions/runs?branch=master&event=push&per_page=20" > "$tmp"; then
    rm -f "$tmp"
    printf 'unknown - %s\n' "$(( $(date +%s) - COMMIT_EPOCH ))"
    return 0
  fi

  status_line="$(python3 -c '
import datetime, json, sys
sha = sys.argv[1]
with open(sys.argv[2], "r", encoding="utf-8") as fh:
    data = json.load(fh)
for run in data.get("workflow_runs", []):
    if run.get("head_sha") != sha or run.get("path") != ".github/workflows/deploy.yml":
        continue
    created = run.get("created_at")
    if created:
        dt = datetime.datetime.fromisoformat(created.replace("Z", "+00:00"))
        age = max(0, int((datetime.datetime.now(datetime.timezone.utc) - dt).total_seconds()))
    else:
        age = 0
    print(run.get("status") or "unknown", run.get("conclusion") or "-", age)
    break
else:
    print("missing", "-", max(0, int(datetime.datetime.now(datetime.timezone.utc).timestamp()) - int(sys.argv[3])))
' "$REMOTE_SHA" "$tmp" "$COMMIT_EPOCH")"
  rm -f "$tmp"
  printf '%s\n' "$status_line"
}

should_fallback() {
  local status conclusion age
  refresh_remote

  if already_deployed; then
    log "$REMOTE_SHA is already deployed."
    return 1
  fi

  if [[ "$FORCE" == "1" ]]; then
    log "Manual fallback requested for $REMOTE_SHA."
    return 0
  fi

  read -r status conclusion age <<<"$(runner_state)"
  log "GitHub workflow state for $REMOTE_SHA: status=$status conclusion=$conclusion age=${age}s"

  case "$status" in
    queued|pending|waiting|requested|missing|unknown)
      if (( age >= THRESHOLD_SECONDS )); then
        return 0
      fi
      log "Grace period has not elapsed yet (${age}s < ${THRESHOLD_SECONDS}s)."
      return 1
      ;;
    in_progress)
      log "GitHub runner is active; local fallback is not needed."
      return 1
      ;;
    completed)
      log "GitHub workflow completed with conclusion=$conclusion; fallback will not bypass CI results."
      return 1
      ;;
    *)
      log "Unrecognised workflow state '$status'; refusing automatic deployment."
      return 1
      ;;
  esac
}

if ! should_fallback; then
  exit 0
fi

exec 9>"$LOCK_FILE"
if [[ "$FORCE" == "1" ]]; then
  flock -w 1800 9
else
  flock -n 9 || { log "Another deployment already owns $LOCK_FILE; skipping."; exit 0; }
fi

if [[ "$FORCE" != "1" ]] && ! should_fallback; then
  exit 0
fi
refresh_remote
SHA="$REMOTE_SHA"

worktree="$(mktemp -d /tmp/flat-finder-fallback.XXXXXX)"
cleanup() {
  git worktree remove --force "$worktree" >/dev/null 2>&1 || true
  rm -rf "$worktree" >/dev/null 2>&1 || true
}
trap cleanup EXIT

git worktree add --quiet --detach "$worktree" "$SHA"

# Keep mutable internal tarballs out of the committed lock while ensuring npm ci
# in the temporary backend build does not reuse a stale integrity entry.
log "Refreshing the temporary backend lockfile."
docker run --rm \
  -v "$worktree:/app" \
  -w /app \
  node:24-slim \
  npm install --prefix backend --package-lock-only --ignore-scripts >/dev/null

base="$SHA^"
if [[ -f "$STATE_DIR/deployed.sha" ]]; then
  candidate="$(cat "$STATE_DIR/deployed.sha")"
  if git cat-file -e "${candidate}^{commit}" 2>/dev/null; then
    base="$candidate"
  fi
fi

ELASTICSEARCH_CHANGED=false
if git diff --name-only "$base" "$SHA" | grep -q '^elasticsearch/'; then
  ELASTICSEARCH_CHANGED=true
fi

log "Building flat-finder application images locally for $SHA."
(
  cd "$worktree"
  export IMAGE_TAG="$SHA"
  docker compose -f docker-compose.yml -f docker-compose.build.yml build \
    flat-finder-backend \
    flat-finder-olx-fetcher \
    flat-finder-olx-fetcher-ua \
    flat-finder-social-fetcher

  if [[ "$ELASTICSEARCH_CHANGED" == "true" ]]; then
    docker compose -f docker-compose.yml -f docker-compose.build.yml build flat-finder-elasticsearch
  fi
)

# Legacy CI used SCP to overwrite these tracked files without advancing the
# server checkout. Restore only those deployment-managed paths before the first
# git-based pull so the fallback cannot be blocked by that old dirty state.
git restore --source=HEAD --staged --worktree -- \
  docker-compose.yml deploy.sh olx-router/nginx.conf scripts/upgrade-postgres-18.sh || true
git pull --ff-only origin master

log "Running guarded local deployment for $SHA."
bash ./scripts/upgrade-postgres-18.sh
DEPLOY_SHA="$SHA" DEPLOY_SOURCE="local-fallback" LOCAL_BUILD=1 \
  bash ./deploy.sh "$SHA" "$ELASTICSEARCH_CHANGED"

log "Fallback deployment completed for $SHA."
