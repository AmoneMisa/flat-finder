# Flat Finder PostgreSQL performance hardening plan

Status: approved implementation complete; production query/index evidence remains intentionally pending, with cursor-scope binding tracked as follow-up hardening
Branch: `perf/postgres-audit-hardening`
PR: `#71`

This plan records the audit findings, implementation order and remaining validation. Changes must preserve search/filter semantics and keep schema ownership in migrations.

## P0 — reduce query work per request

### 1. Dedicated map query path
- [x] Replace page-by-page reuse of `searchPostgresListings()` in `map-feed.js` with one narrow PostgreSQL query for map points.
- [x] Select only fields required by map markers/cards.
- [x] Preserve active/public visibility rules and `dedupe_key` representative semantics.
- [x] Cap results in SQL rather than iterating 60-row pages.
- [x] Do not run market comparison for every map point; selected/full cards keep enrichment on the normal listing path.
- [x] Add regression/integration coverage for map filter parity, radius and dedupe.
- [x] Count coordinate-bearing points separately so `truncated` does not become true merely because some listings have no coordinates.

### 2. Stop repeated exact counts on cursor pagination
- [x] Carry the first-page exact total inside the cursor.
- [x] Skip the exact count query on subsequent cursor pages when the cursor contains that total.
- [x] Preserve explicit stats/count-only API behaviour and legacy cursors.
- [x] Add cursor-pagination regression tests.
- [x] Use `LIMIT + 1` internally so `nextCursor` is emitted only when another row definitely exists, avoiding a terminal empty request.
- [x] Reject carried counts from cursors whose sort does not match the active request.
- [ ] Bind newly issued cursors to a fingerprint of the normalized query scope (countries + semantic filters). A cursor with an explicit mismatched scope must be rejected; legacy unscoped cursors may remain positional for compatibility but must not supply a trusted carried count.

### 3. Move hot scalar JSONB filters to typed columns
- [x] Inventory scalar filters cast/read from JSONB (`bedrooms`, `floor`, `totalFloors`, `buildingYear`, `commissionPercent`, `metroDistance`, etc.).
- [x] Add STORED generated typed columns so current ingestion does not need duplicate field-maintenance logic.
- [x] Replace runtime JSONB casts in hot search predicates with typed columns.
- [x] Add selective country/city/filter indexes rather than every possible filter combination.
- [x] Keep JSONB as source/enrichment payload, not the hot scalar filter layer.
- [x] Materialize all eight STORED listing scalars, including `lat/lng`, in one `ALTER TABLE` so deployment rewrites the listings heap once.
- [x] Build scalar/spatial indexes in the following migration so the longer index-build phase does not inherit the generated-column migration's `ACCESS EXCLUSIVE` lock.

### 4. Normalize repeated-array geo/nearby filters
- [x] Add normalized relation tables for location terms and nearby-place facts.
- [x] Backfill current listing payloads.
- [x] Maintain them transactionally from listing writes.
- [x] Rebuild relation rows only when the owning JSON fragments change, not on unrelated `data` updates.
- [x] Replace `jsonb_array_elements*` request-time predicates with indexed `EXISTS`/semi-joins.
- [x] Add bounded domain types and indexes for `(type, normalized_name, listing_id)` and `(kind, distance_m, listing_id)` access paths.
- [x] Bound upstream-derived materialized helper labels before writing them so a pathological source value cannot fail the owning listing insert/update.

### 5. Spatial/radius search
- [x] Add indexable `lat/lng` representation and bounding-box prefiltering as the non-PostGIS interim path.
- [x] Apply exact spherical distance only to the bounded candidate set.
- [x] Reuse the same predicate builder for list and map filters.
- [x] Build the bounding box from the same `R=6_371_000 m` spherical model as the exact predicate, including conservative longitude handling near poles/dateline.
- [x] Add an explicit 999 m / 1001 m boundary regression proving bbox and exact distance agree at a 1000 m radius.

## P0 — concurrency correctness that also reduces waste

### 6. Mobile notification delivery coordination
- [x] Replace process-local-only scanner coordination with a PostgreSQL advisory lock across replicas.
- [x] Turn the delivery ledger into durable `sending/sent/failed` state with claim lease/token.
- [x] Only a process that successfully claims a delivery may call FCM.
- [x] Make seen writes/probes set-based instead of per-item N+1 reads/writes.
- [x] Put a stable `deliveryId` in the push payload to support client-side crash-window dedupe.
- [x] Add a transport-level multi-worker integration test around the FCM boundary: four independent scanner processes share PostgreSQL, use mocked FX/OAuth/FCM HTTP boundaries, and must emit exactly one push plus durable `sent`/seen state.

### 7. Atomic property-cluster merge
- [x] Move discovery, canonical cluster selection, merge and member upsert into one database transaction/function.
- [x] Serialize overlapping merges with transaction-scoped advisory locks acquired in deterministic order.
- [x] Replace member-by-member upserts with set-based `jsonb_to_recordset` operations.
- [x] Preserve propagation back to `listings.data.propertyClusterId`, generated `dedupe_key` and public-feed read model.
- [x] Add concurrent overlapping-merge integration coverage.

## P1 — query/index and background-work cleanup

### 8. Evidence-driven index/read-model/queue cleanup
- [x] Add `backend/scripts/postgres-performance-report.sql` for connection pressure, `pg_stat_statements`, index usage, dead tuples, queue and mobile outbox state.
- [x] Make the report continue with index/table/queue metrics when `pg_stat_statements` is not installed.
- [x] Execute the report under `psql -v ON_ERROR_STOP=1` in the PostgreSQL 18 CI gate.
- [ ] Capture production `pg_stat_statements` and `EXPLAIN (ANALYZE, BUFFERS)` after representative traffic.
- [ ] Remove/reshape old indexes only from production evidence (`pg_stat_user_indexes`), not from static guesses.
- [x] Rework `listing_public_feed_members` trigger from unconditional delete+insert to conditional upsert/delete.
- [x] Bulk enqueue crawl tasks through `jsonb_to_recordset` instead of one INSERT round trip per task.
- [x] Throttle expired-task recovery and serialize it across replicas instead of running a full recovery update before every claim.
- [x] Remove extra in-process PostgreSQL pools from hiring/place storage and reuse the main backend pool.
- [x] Add query-shape/query-count regression assertions where practical.

## Perceptual-photo matching

- [x] Stop choosing only the newest N perceptual hashes for an entire country before Hamming distance.
- [x] Add eight indexed 8-bit perceptual-hash bands.
- [x] Use band matches as the candidate set and exact Hamming distance as the final check.
- [x] Cap the accepted Hamming threshold at 7, which guarantees at least one exact 8-bit band match for every accepted candidate.
- [x] Add a recall regression with an old distance-7 match behind more than 800 newer country hashes.

## Short text / column type hygiene

`TEXT` and `VARCHAR(n)` have the same PostgreSQL storage representation. This work is data-contract hardening, not a query-speed optimization.

- [x] Create new normalized search relation dimensions with bounded `VARCHAR` types from the start.
- [x] Convert application-controlled queue fields to bounded `VARCHAR`; convert queue lease token from `TEXT` to native `UUID`.
- [x] Bound place labels that are already normalized at ingestion while keeping upstream-owned `external_id` as `TEXT`.
- [x] Bound learned-geography metadata while keeping free-form query/provider identifiers as `TEXT`.
- [x] Bound mobile preset names.
- [x] Fail migrations on oversized legacy values instead of silently truncating them.
- [x] Keep trigger/generated-column-bound columns (`listings` hot labels and `listing_property_clusters.cluster_id`) as `TEXT` in automatic deploy migrations; PostgreSQL CI demonstrated that changing them requires dependency teardown/rebuild, with no storage/performance gain.
- [ ] Revisit those dependency-bound types only in a maintenance window if there is a concrete schema-contract reason, not for query speed.

## Validation gates

1. Pull requests touching backend code run against PostgreSQL 18 before merge.
2. All migrations must apply from an empty database in CI.
3. A production-like upgrade test must create a database at schema version `023`, insert representative legacy rows, apply `024–032`, and preserve data while materializing the new search/outbox structures.
4. Migration `032` must fail before type conversion when an oversized legacy value exists; CI verifies that the failed attempt rolls back without truncating the value, after which a clean retry succeeds.
5. The production performance-report SQL must execute through real `psql -v ON_ERROR_STOP=1` even when `pg_stat_statements` is unavailable.
6. Existing backend tests and new regression/integration tests must pass; current hardening gate is **296/296** on PostgreSQL 18.6.
7. Multi-process notification delivery must cross the mocked FCM transport boundary only once for one logical delivery.
8. Compare SQL query count before/after for affected request paths.
9. Use `EXPLAIN (ANALYZE, BUFFERS)` on representative production-like/production data before deleting or adding final indexes.
10. Avoid application-local parsing/geography logic that belongs in `@whiteslove/parsing-lexicon` or `@whiteslove/geo-catalog`.
