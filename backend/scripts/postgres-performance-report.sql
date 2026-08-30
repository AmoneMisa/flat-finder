-- Flat Finder production performance report.
-- Run against the production database after representative traffic has warmed
-- pg_stat_statements. This script is read-only and still reports index/table
-- pressure when pg_stat_statements is unavailable.

\echo '=== database / connection summary ==='
SELECT
  current_database() AS database,
  current_setting('max_connections')::integer AS max_connections,
  COUNT(*) AS current_connections,
  COUNT(*) FILTER (WHERE state = 'active') AS active_connections,
  COUNT(*) FILTER (WHERE wait_event IS NOT NULL) AS waiting_connections
FROM pg_stat_activity
WHERE datname = current_database();

SELECT EXISTS (
  SELECT 1
  FROM pg_extension
  WHERE extname = 'pg_stat_statements'
) AS has_pg_stat_statements
\gset

\if :has_pg_stat_statements
\echo '=== top statements by total execution time ==='
SELECT
  calls,
  ROUND(total_exec_time::numeric, 2) AS total_ms,
  ROUND(mean_exec_time::numeric, 2) AS mean_ms,
  ROUND(max_exec_time::numeric, 2) AS max_ms,
  rows,
  shared_blks_hit,
  shared_blks_read,
  temp_blks_written,
  LEFT(REGEXP_REPLACE(query, '\\s+', ' ', 'g'), 500) AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY total_exec_time DESC
LIMIT 30;

\echo '=== top statements by mean execution time (minimum 20 calls) ==='
SELECT
  calls,
  ROUND(mean_exec_time::numeric, 2) AS mean_ms,
  ROUND(max_exec_time::numeric, 2) AS max_ms,
  rows,
  shared_blks_hit,
  shared_blks_read,
  temp_blks_written,
  LEFT(REGEXP_REPLACE(query, '\\s+', ' ', 'g'), 500) AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND calls >= 20
ORDER BY mean_exec_time DESC
LIMIT 30;
\else
\echo '=== pg_stat_statements unavailable ==='
\echo 'Enable/load pg_stat_statements to collect statement timing; continuing with index/table statistics.'
\endif

\echo '=== listing indexes by scan count / size ==='
SELECT
  s.schemaname,
  s.relname AS table_name,
  s.indexrelname AS index_name,
  s.idx_scan,
  s.idx_tup_read,
  s.idx_tup_fetch,
  pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size
FROM pg_stat_user_indexes s
WHERE s.relname IN (
  'listings',
  'listing_public_feed_members',
  'listing_location_terms',
  'listing_nearby_places',
  'listing_photo_hashes',
  'listing_property_clusters',
  'crawl_tasks'
)
ORDER BY s.relname, s.idx_scan DESC, pg_relation_size(s.indexrelid) DESC;

\echo '=== table IO / dead tuple pressure ==='
SELECT
  schemaname,
  relname,
  seq_scan,
  idx_scan,
  n_live_tup,
  n_dead_tup,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  last_autovacuum,
  last_autoanalyze
FROM pg_stat_user_tables
WHERE (schemaname = 'public' AND relname IN (
  'listings',
  'listing_public_feed_members',
  'listing_location_terms',
  'listing_nearby_places',
  'listing_photo_hashes',
  'listing_property_clusters',
  'crawl_tasks'
)) OR (schemaname = 'subscriptions' AND relname IN (
  'mobile_deliveries',
  'mobile_subscription_seen'
))
ORDER BY n_dead_tup DESC;

\echo '=== queue backlog / leases ==='
SELECT
  status,
  COUNT(*) AS tasks,
  MIN(run_after) AS oldest_run_after,
  MIN(locked_until) FILTER (WHERE status = 'running') AS earliest_lease_expiry
FROM crawl_tasks
GROUP BY status
ORDER BY status;

\echo '=== mobile delivery outbox ==='
SELECT
  status,
  COUNT(*) AS deliveries,
  MIN(updated_at) AS oldest_updated_at,
  MAX(attempts) AS max_attempts
FROM subscriptions.mobile_deliveries
GROUP BY status
ORDER BY status;
