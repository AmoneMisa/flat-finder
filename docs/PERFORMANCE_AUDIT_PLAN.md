# Flat Finder PostgreSQL performance hardening plan

Status: active
Branch: `perf/postgres-audit-hardening`

This plan records the audit findings and the implementation order. Changes should preserve search/filter semantics and keep schema ownership in migrations.

## P0 — reduce query work per request

### 1. Dedicated map query path
- [ ] Replace page-by-page reuse of `searchPostgresListings()` in `map-feed.js` with one narrow PostgreSQL query for map points.
- [ ] Select only fields required by map markers/cards.
- [ ] Preserve active/public visibility rules and `dedupe_key` representative semantics.
- [ ] Cap results in SQL rather than iterating 60-row pages.
- [ ] Do not run market comparison for every map point; enrich selected/visible listings through the normal listing/card path instead.
- [ ] Add regression/integration tests for map filter parity and dedupe.

### 2. Stop repeated exact counts on cursor pagination
- [ ] Return an exact count only on the first page when requested.
- [ ] Subsequent cursor pages should use `LIMIT + 1` / `nextCursor` and skip exact `COUNT(DISTINCT ...)`.
- [ ] Preserve explicit stats/count-only API behaviour.
- [ ] Add cursor-pagination regression tests.

### 3. Move hot scalar JSONB filters to typed columns
- [ ] Inventory scalar filters currently cast/read from JSONB (`bedrooms`, `floor`, `totalFloors`, `buildingYear`, `commissionPercent`, `metroDistance`, etc.).
- [ ] Add typed columns/backfill in a migration.
- [ ] Populate them in the canonical listing write path.
- [ ] Replace runtime JSONB casts in search predicates with typed columns.
- [ ] Add selective indexes based on actual query shapes, not every possible filter combination.
- [ ] Keep JSONB as source/enrichment payload, not the hot filter storage layer.

### 4. Normalize repeated-array geo/nearby filters
- [ ] Add normalized relation tables for location terms and nearby-place facts.
- [ ] Backfill from current listing payloads.
- [ ] Maintain them transactionally from listing writes.
- [ ] Replace `jsonb_array_elements*` filter predicates with indexed `EXISTS`/semi-joins.
- [ ] Add indexes for `(type, normalized_name, listing_id)` and `(kind, distance_m, listing_id)` style access paths.

### 5. Spatial/radius search
- [ ] Introduce an indexed spatial representation (PostGIS when available) or, as an interim step, indexed `lat/lng` bounding-box prefiltering.
- [ ] Apply exact distance only to the bounded candidate set.
- [ ] Reuse the same spatial predicate for map and radius filters.
- [ ] Add radius correctness tests near boundary values.

## P0 — concurrency correctness that also reduces waste

### 6. Mobile notification delivery coordination
- [ ] Replace process-local scanner coordination with PostgreSQL coordination.
- [ ] Add a durable delivery/outbox state with unique delivery identity and claim/lease token.
- [ ] Only the process that successfully claims a delivery may call FCM.
- [ ] Make seen/delivery writes set-based where possible; remove per-item N+1 probes.
- [ ] Keep stable delivery IDs in push payloads so clients can suppress rare crash-window duplicates.
- [ ] Add multi-worker concurrency tests.

### 7. Atomic property-cluster merge
- [ ] Wrap cluster discovery, canonical cluster selection, merge and member upsert in one transaction.
- [ ] Serialize overlapping merges with a transaction-scoped advisory lock based on deterministic member/cluster identity.
- [ ] Replace member-by-member upserts with a set-based/bulk upsert.
- [ ] Ensure propagation back to `listings.data.propertyClusterId`, `dedupe_key` and feed read-model remains consistent.
- [ ] Add concurrent merge integration tests.

## P1 — query/index and background-work cleanup

### 8. Evidence-driven index/read-model/queue cleanup
- [ ] Capture production `pg_stat_statements` and `EXPLAIN (ANALYZE, BUFFERS)` for representative slow searches.
- [ ] Add/remove indexes based on the final query shapes and `pg_stat_user_indexes` usage.
- [ ] Rework `listing_public_feed_members` trigger from unconditional delete+insert toward conditional upsert/delete to reduce write amplification.
- [ ] Bulk enqueue crawl tasks instead of one INSERT round trip per task.
- [ ] Move expired-task recovery out of every `claimTask()` call into a bounded periodic recovery path.
- [ ] Audit all PostgreSQL pools and enforce one connection-budget policy across backend processes.
- [ ] Add timing/query-count assertions where practical.

## Perceptual-photo matching follow-up

- [ ] Stop selecting only the newest N perceptual hashes for an entire country before computing Hamming distance.
- [ ] Add indexed perceptual-hash buckets/bands to form a small candidate set first.
- [ ] Run exact Hamming distance only on candidates from matching buckets.
- [ ] Add recall tests proving older valid matches are not silently excluded.

## Validation gates

For each implementation slice:

1. Existing backend tests must continue to pass.
2. Add regression tests for changed query/concurrency semantics.
3. Compare SQL query count before/after for the affected request.
4. Use `EXPLAIN (ANALYZE, BUFFERS)` on representative production-like data before adding final indexes.
5. Avoid adding application-local parsing/geography logic that belongs in `@whiteslove/parsing-lexicon` or `@whiteslove/geo-catalog`.
