# PostgreSQL production validation

This runbook captures production evidence for the PostgreSQL hardening work without guessing from static code. It is intentionally separated from the migration implementation because the remaining acceptance criteria depend on real production workload, table size, index usage, and lock-window tolerance.

## Current pre-deploy baseline

Observed on 2026-08-31 before deploying migrations 024-032:

- PostgreSQL image: `postgres:18-alpine`.
- Production backend image is still based on `94732401e8eae324db685a69ffdb4396a91ecd52`; the hardening branch is not deployed.
- `listings`: approximately 248,962 live rows, 42,3xx dead rows, 515 MB heap, 435 MB indexes, and about 1.95 GB total relation size.
- The difference between heap + indexes and total relation size indicates substantial TOAST storage; keep full listing payloads out of narrow search/map paths where possible.
- `listing_public_feed_members`: approximately 52k live rows and 3.5k dead rows.
- `listing_property_clusters` is currently empty but has accumulated a large number of scans, so its call pattern should be verified from statement-level evidence before drawing conclusions.
- `pg_stat_statements` is not installed and `shared_preload_libraries` is currently empty.

These counters are cumulative and do not identify which SQL statements are expensive. Do not delete indexes or change query semantics from these counters alone.

## 1. Capture the read-only baseline

Run the existing report against production before enabling or deploying anything:

```bash
psql -v ON_ERROR_STOP=1 -f backend/scripts/postgres-performance-report.sql
```

For Docker deployments where the SQL file is on the host:

```bash
docker exec -i <postgres-container> sh -lc \
  'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < backend/scripts/postgres-performance-report.sql
```

Also capture relation/TOAST size, vacuum state, full index usage, and database-level IO:

```sql
SELECT
  c.relname AS table_name,
  pg_size_pretty(pg_relation_size(c.oid)) AS heap,
  pg_size_pretty(pg_indexes_size(c.oid)) AS indexes,
  pg_size_pretty(
    CASE
      WHEN c.reltoastrelid <> 0 THEN pg_total_relation_size(c.reltoastrelid)
      ELSE 0
    END
  ) AS toast,
  pg_size_pretty(pg_total_relation_size(c.oid)) AS total
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;

SELECT
  relname,
  n_live_tup,
  n_dead_tup,
  ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
  last_vacuum,
  last_autovacuum,
  last_analyze,
  last_autoanalyze,
  vacuum_count,
  autovacuum_count,
  analyze_count,
  autoanalyze_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

SELECT
  schemaname,
  relname AS table_name,
  indexrelname AS index_name,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC, idx_scan ASC;

SELECT
  datname,
  numbackends,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_pct,
  temp_files,
  pg_size_pretty(temp_bytes) AS temp_bytes,
  deadlocks
FROM pg_stat_database
WHERE datname = current_database();
```

Record the capture timestamp and PostgreSQL uptime alongside the results. `pg_stat_*` counters are cumulative, so a snapshot without its observation window can be misleading.

## 2. Enable `pg_stat_statements`

This step changes PostgreSQL configuration and requires a PostgreSQL restart. Do it during an accepted maintenance window. Do not combine it with migrations 024-032; collect workload evidence first.

Check that the extension files are available:

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE name = 'pg_stat_statements';
```

If available, configure preload as the PostgreSQL superuser:

```sql
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
```

If production already has other libraries configured, preserve them instead of replacing the list. Verify the effective configuration source before restart:

```sql
SELECT name, setting, source, sourcefile
FROM pg_settings
WHERE name = 'shared_preload_libraries';
```

Restart only PostgreSQL using the deployment's normal orchestration path. After restart:

```sql
SHOW shared_preload_libraries;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT extname, extversion
FROM pg_extension
WHERE extname = 'pg_stat_statements';
```

Do not call `pg_stat_statements_reset()` after enabling it. We need a representative observation window.

## 3. Warm a representative workload

Let normal production traffic run long enough to cover the important paths:

- default listing feed;
- filtered listing search;
- city and geo filters;
- map feed;
- mobile subscription scans;
- crawl queue activity;
- photo duplicate checks;
- property-cluster merge traffic if it naturally occurs.

A few hours can expose obvious hot statements; roughly one normal traffic day is preferable before making index-removal decisions.

Capture the PostgreSQL restart time / statistics observation start so calls and total time are interpreted over the same window.

## 4. Rank real statements

Run `backend/scripts/postgres-performance-report.sql` again after the observation window. At minimum preserve:

- top statements by total execution time;
- top statements by mean execution time with a minimum call threshold;
- calls;
- rows;
- shared block hits and reads;
- temporary block writes;
- index scan counts and sizes;
- dead tuple and autovacuum state.

Prioritize statements by workload impact, not merely by one slow execution. A high-call 10 ms query can be a larger production cost than a rare 500 ms query.

## 5. Capture representative `EXPLAIN` evidence

Only run `EXPLAIN (ANALYZE, ...)` for known `SELECT` statements during an acceptable load window. `ANALYZE` executes the statement. Never use `EXPLAIN ANALYZE` on production `INSERT`, `UPDATE`, `DELETE`, or other mutating statements merely for diagnosis.

For a representative read query:

```sql
BEGIN;
SET LOCAL statement_timeout = '15s';
SET LOCAL lock_timeout = '2s';

EXPLAIN (
  ANALYZE,
  BUFFERS,
  WAL,
  SETTINGS,
  SUMMARY,
  FORMAT TEXT
)
SELECT ...;

ROLLBACK;
```

Capture at least one representative plan for each production-hot listing path that appears in `pg_stat_statements`:

1. default/public feed;
2. general filtered search;
3. geo/location filter;
4. radius/spatial filter if present in real traffic;
5. map feed.

Use real-but-non-secret parameter values representative of normal traffic. Do not invent worst-case predicates that users do not execute.

For write statements, use plain `EXPLAIN` without `ANALYZE` on production, or reproduce them against staging / a production-shaped copy.

## 6. Index decision gate

Do not remove a legacy index unless all of the following are true:

- its production `idx_scan` remains negligible over a representative observation window;
- no hot `pg_stat_statements` query relies on it;
- representative `EXPLAIN (ANALYZE, BUFFERS)` plans remain acceptable without it in a safe test environment;
- the index is not required for a uniqueness or constraint contract;
- write amplification / storage savings justify removal.

A zero or low scan count immediately after restart is not evidence of an unused index.

## 7. Migration 024-026 deployment gate

The current migration runner executes migrations transactionally. This has real lock implications:

- `024` adds STORED generated columns and rewrites `listings` under `ACCESS EXCLUSIVE`;
- `025` creates relation-maintenance triggers and backfills normalized search relations in one transaction to avoid missing concurrent writes;
- `026` uses ordinary transactional `CREATE INDEX`, which can block writes while each index is built.

Before deploying, capture production values for:

```sql
SELECT
  pg_size_pretty(pg_relation_size('public.listings')) AS listings_heap,
  pg_size_pretty(pg_total_relation_size('public.listings')) AS listings_total,
  n_live_tup,
  n_dead_tup
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND relname = 'listings';

SELECT
  current_setting('statement_timeout') AS statement_timeout,
  current_setting('lock_timeout') AS lock_timeout,
  current_setting('max_connections') AS max_connections;
```

The already observed production `listings` relation is large enough that the lock window must be treated as an explicit operational decision, not described as zero-downtime.

If the accepted maintenance window is shorter than a production-shaped rehearsal of 024-026, stop and implement staged/no-transaction migration support before deployment. That path should include online index builds with `CREATE INDEX CONCURRENTLY` and a race-safe relation backfill/catch-up protocol; simply moving trigger creation after the backfill is incorrect because concurrent writes can be missed.

## 8. Before/after comparison

After the hardening branch is eventually deployed and normal traffic has warmed again, capture the same report over a comparable observation window and compare:

- total and mean execution time of listing search paths;
- calls and rows per search statement;
- shared blocks read vs hit;
- temp block writes;
- sequential vs index scan behavior;
- index sizes and scan counts;
- `listings` and normalized relation sizes;
- dead tuple/autovacuum pressure;
- queue/outbox backlog;
- application-level latency/error metrics if available.

Do not compare cumulative counters across unequal restart/statistics windows without normalizing by elapsed time or workload.

## Acceptance evidence still required

The PostgreSQL hardening PR is not production-validated until we have:

- a representative production `pg_stat_statements` snapshot;
- representative `EXPLAIN (ANALYZE, BUFFERS)` plans for the hot read paths;
- production `pg_stat_user_indexes` evidence before any legacy-index removal;
- a measured or production-shaped estimate for migration 024-026 lock/build duration;
- an explicit maintenance-window decision, or staged/no-transaction migration support if that window is unacceptable.

Until then, keep the PR draft and do not describe migrations 024-026 as zero-downtime.
