#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

service="flat-finder-postgres"
old_container="$(docker compose ps -q "$service")"
if [[ -z "$old_container" ]]; then
  echo "[postgres-upgrade] $service is not running; refusing to guess the source volume" >&2
  exit 1
fi

current_version="$(docker exec "$old_container" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atqc "SHOW server_version_num"' | tr -d '\r')"
current_major=$((current_version / 10000))

if (( current_major >= 18 )); then
  echo "[postgres-upgrade] PostgreSQL $current_major is already active; nothing to do"
  exit 0
fi

if (( current_major != 17 )); then
  echo "[postgres-upgrade] expected PostgreSQL 17, found server_version_num=$current_version" >&2
  exit 1
fi

project="$(docker inspect "$old_container" --format '{{ index .Config.Labels "com.docker.compose.project" }}')"
if [[ -z "$project" ]]; then
  echo "[postgres-upgrade] cannot determine Docker Compose project name" >&2
  exit 1
fi

new_volume="${project}_flat-finder-postgres-data-v18"
temp_container="${project}-postgres18-migration"
backup_dir="${POSTGRES_UPGRADE_BACKUP_DIR:-./backups/postgres-18}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_file="$backup_dir/flatfinder-pg17-$timestamp.dump"
env_file="$backup_dir/.postgres18-$timestamp.env"

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
umask 077

docker inspect "$old_container" --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | grep -E '^POSTGRES_(DB|USER|PASSWORD|INITDB_ARGS|HOST_AUTH_METHOD)=' > "$env_file"

cleanup() {
  rm -f "$env_file"
  docker rm -f "$temp_container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

reset_old_read_only() {
  if docker ps --format '{{.ID}}' | grep -qx "$old_container"; then
    docker exec -i "$old_container" sh -c 'psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 -v target_db="$POSTGRES_DB"' <<'SQL' >/dev/null || true
SELECT format('ALTER DATABASE %I RESET default_transaction_read_only', :'target_db') \gexec
SQL
  fi
}

# PostgreSQL 18 changed the official image's PGDATA/VOLUME layout. Use a fresh
# v18 volume and keep the old v17 volume untouched for rollback.
docker rm -f "$temp_container" >/dev/null 2>&1 || true
docker volume rm "$new_volume" >/dev/null 2>&1 || true
docker volume create "$new_volume" >/dev/null

echo "[postgres-upgrade] preparing PostgreSQL 18 volume $new_volume"
docker run -d \
  --name "$temp_container" \
  --env-file "$env_file" \
  -v "$new_volume:/var/lib/postgresql" \
  postgres:18-alpine >/dev/null

for _ in $(seq 1 60); do
  if docker exec "$temp_container" sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

docker exec "$temp_container" sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null

# Block new writes before the final dump. Existing clients are disconnected so
# reconnecting application processes inherit the read-only database default.
echo "[postgres-upgrade] freezing writes on PostgreSQL 17"
docker exec -i "$old_container" sh -c 'psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 -v target_db="$POSTGRES_DB"' <<'SQL'
SELECT format('ALTER DATABASE %I SET default_transaction_read_only = on', :'target_db') \gexec
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = :'target_db'
  AND pid <> pg_backend_pid();
SQL

migration_ok=0
trap 'if [[ "$migration_ok" != "1" ]]; then reset_old_read_only; fi; cleanup' EXIT

echo "[postgres-upgrade] creating final PostgreSQL 17 backup: $backup_file"
docker exec "$old_container" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc --no-owner --no-privileges' > "$backup_file"

if [[ ! -s "$backup_file" ]]; then
  echo "[postgres-upgrade] backup is empty" >&2
  exit 1
fi

echo "[postgres-upgrade] restoring into PostgreSQL 18"
cat "$backup_file" | docker exec -i "$temp_container" sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges --exit-on-error'

docker exec "$temp_container" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -Atqc "SELECT current_setting('"'"'server_version_num'"'"'), to_regclass('"'"'public.listings'"'"') IS NOT NULL"' | grep -q '^18[0-9][0-9][0-9][0-9][0-9]|t$'

echo "[postgres-upgrade] switching Compose service to PostgreSQL 18"
docker stop "$old_container" >/dev/null
docker stop "$temp_container" >/dev/null

docker compose up -d "$service"

new_container="$(docker compose ps -q "$service")"
for _ in $(seq 1 60); do
  health="$(docker inspect "$new_container" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || true)"
  if [[ "$health" == "healthy" ]]; then
    break
  fi
  sleep 2
done

health="$(docker inspect "$new_container" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}')"
if [[ "$health" != "healthy" ]]; then
  echo "[postgres-upgrade] PostgreSQL 18 did not become healthy; old v17 volume is still preserved" >&2
  exit 1
fi

new_version="$(docker exec "$new_container" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atqc "SHOW server_version_num"' | tr -d '\r')"
if (( new_version / 10000 != 18 )); then
  echo "[postgres-upgrade] expected PostgreSQL 18 after switch, got $new_version" >&2
  exit 1
fi

migration_ok=1
echo "[postgres-upgrade] PostgreSQL 18 migration complete; backup kept at $backup_file"
echo "[postgres-upgrade] old PostgreSQL 17 volume was not deleted"
