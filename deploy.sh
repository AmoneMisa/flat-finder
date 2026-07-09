#!/usr/bin/env bash
# Standalone deploy for the flat-finder backend stack. Run on the server (or via
# the GitHub Actions SSH step). Rebuilds and restarts only this compose project.
set -euo pipefail

cd "$(dirname "$0")"

# Pull latest code if this is a git checkout on the server.
if [ -d .git ]; then
  git pull --ff-only
fi

docker compose pull || true
docker compose up -d --build
docker compose ps
