# Flat Finder PostgreSQL performance hardening plan

Status: implementation mostly complete; CI/production validation active
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
- [ ] Use `LIMIT + 1` internally so `nextCursor` is emitted only when another row definitely exists, rather than on an exact page boundary.

### 3. Move hot scalar JSONB filters to typed columns
- [x] Inventory scalar filters cast/read from JSONB (`bedrooms`, `floor`, `totalFloors`, `buildingYear`, `commissionPercent`, `metroDistance`, etc.).
- [x] Add STORED generated typed columns so current ingestion does not need duplicate field-maintenance logic.
- [x] Replace runtime JSONB casts in hot search predicates with typed columns.
- [x] Add selective country/city/filter indexes rather than every possible filter combination.
- [x] Keep JSONB as source/enrichment payload, not the hot scalar filter layer.

### 4. Normalize repeated-array geo/nearby filters
- [x] Add normalized relation tables for location terms and nearby-place facts.
- [x] Backfill current listing payloads.
- [x] Maintain them transactionally from listing writes.
- [x] Rebuild relation rows only when the owning JSON fragments change, not on unrelated `data` updates.
- [x] Replace `jsonb_array_elements*` request-time predicates with indexed `EXISTS`/semi-joins.
- [x] Add bounded domain types and indexes for `(type, normalized_name, listing_id)` and `(kind, distance_m, listing_id)` access paths.

### 5. Spatial/radius search
- [x] Add indexable `lat/lng` representation and bounding-box prefiltering as the non-PostGIS interim path.
- [x] Apply exact Haversine distance only to the bounded candidate set.
- [x] Reuse the same predicate builder for list and map filters.
- [x] Add integration coverage for radius filtering.
- [ ] Add explicit near-boundary numerical tests before considering this spatial work fully frozen.

## P0 — concurrency correctness that also reduces waste

### 6. Mobile notification delivery coordination
- [x] Replace process-local-only scanner coordination with a PostgreSQL advisory lock across replicas.
- [x] Turn the delivery ledger into durable `sending/sent/failed` state with claim lease/token.
- [x] Only a process that successfully claims a delivery may call FCM.
- [x] Make seen writes/probes set-based instead of per-item N+1 reads/writes.
- [x] Put a stable `deliveryId` in the push payload to support client-side crash-window dedupe.
- [ ] Add a transport-level multi-worker integration test around the FCM boundary; DB coordination is covered structurally but FCM itself is not exercised in CI.

### 7. Atomic property-cluster merge
- [x] Move discovery, canonical cluster selection, merge and member upsert into one database transaction/function.
- [x] Serialize overlapping merges with transaction-scoped advisory locks acquired in deterministic order.
- [x] Replace member-by-member upserts with set-based `jsonb_to_recordset` operations.
- [x] Preserve propagation back to `listings.data.propertyClusterId`, generated `dedupe_key` and public-feed read model.
- [x] Add concurrent overlapping-merge integration coverage.

## P1 — query/index and background-work cleanup

### 8. Evidence-driven index/read-model/queue cleanup
- [x] Add `backend/scripts/postgres-performance-report.sql` for connection pressure, `pg_stat_statements`, index usage, dead tuples, queue and mobile outbox state.
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
- [ ] Add a dedicated recall regression proving an old-but-valid perceptual match remains discoverable after many newer hashes exist.

## Short text / column type hygiene

`TEXT` and `VARCHAR(n)` have the same PostgreSQL storage representation. This work is data-contract hardening, not a query-speed optimization.

- [x] Create new normalized search relation dimensions with bounded `VARCHAR` types from the start.
- [x] Convert application-controlled queue fields to bounded `VARCHAR`; convert queue lease token from `TEXT` to native `UUID`.
- [x] Bound place labels that are already normalized at ingestion while keeping upstream-owned `external_id` as `TEXT`.
- [x] Bound learned-geography metadata while keeping free-form query/provider identifiers as `TEXT`.
- [x] Bound property cluster IDs and mobile preset names.
- [x] Fail the migration on oversized legacy values instead of silently truncating them.
- [ ] Do not automatically alter hot `listings` label columns: `city` participates in generated `dedupe_key`, and indexed label type changes can require dependency/index rebuilds under an exclusive lock. Revisit only in a maintenance window if production evidence justifies it.

## Validation gates

1. Pull requests touching backend code run against PostgreSQL 18 before merge.
2. All migrations must apply from an empty database in CI.
3. Existing backend tests and new regression/integration tests must pass.
4. Compare SQL query count before/after for affected request paths.
5. Use `EXPLAIN (ANALYZE, BUFFERS)` on representative production-like/production data before deleting or adding final indexes.
6. Avoid application-local parsing/geography logic that belongs in `@whiteslove/parsing-lexicon` or `@whiteslove/geo-catalog`.
