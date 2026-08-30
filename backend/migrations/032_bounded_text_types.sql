-- TEXT and VARCHAR use the same PostgreSQL storage representation. These
-- changes are about schema discipline and rejecting accidental huge values,
-- not about storage/query-speed gains.
--
-- Do NOT alter the hot listings label columns here. city participates in the
-- generated dedupe_key and district/metro have active indexes; ALTER TYPE can
-- require dependency/index rebuilds under an ACCESS EXCLUSIVE lock. That work
-- belongs in an explicit maintenance window after production measurements.
--
-- IMPORTANT: explicit casts to VARCHAR(n) can truncate. Validate first and fail
-- loudly instead of silently modifying production data.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM crawl_tasks WHERE char_length(crawl_generation) > 128) THEN
    RAISE EXCEPTION 'Cannot bound crawl_tasks.crawl_generation to varchar(128)';
  END IF;
  IF EXISTS (SELECT 1 FROM crawl_tasks WHERE char_length(type) > 64) THEN
    RAISE EXCEPTION 'Cannot bound crawl_tasks.type to varchar(64)';
  END IF;
  IF EXISTS (SELECT 1 FROM crawl_tasks WHERE char_length(country) > 8) THEN
    RAISE EXCEPTION 'Cannot bound crawl_tasks.country to varchar(8)';
  END IF;
  IF EXISTS (SELECT 1 FROM crawl_tasks WHERE char_length(status) > 16) THEN
    RAISE EXCEPTION 'Cannot bound crawl_tasks.status to varchar(16)';
  END IF;
  IF EXISTS (SELECT 1 FROM crawl_tasks WHERE char_length(locked_by) > 200) THEN
    RAISE EXCEPTION 'Cannot bound crawl_tasks.locked_by to varchar(200)';
  END IF;
  IF EXISTS (SELECT 1 FROM crawl_task_runs WHERE char_length(crawl_generation) > 128) THEN
    RAISE EXCEPTION 'Cannot bound crawl_task_runs.crawl_generation to varchar(128)';
  END IF;
  IF EXISTS (
    SELECT 1 FROM crawl_tasks
    WHERE lock_token IS NOT NULL
      AND lock_token !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ) THEN
    RAISE EXCEPTION 'Cannot convert crawl_tasks.lock_token to uuid: invalid values exist';
  END IF;

  IF EXISTS (SELECT 1 FROM listing_property_clusters WHERE char_length(cluster_id) > 128) THEN
    RAISE EXCEPTION 'Cannot bound listing_property_clusters.cluster_id to varchar(128)';
  END IF;

  IF EXISTS (SELECT 1 FROM learned_geo WHERE char_length(country) > 8) THEN
    RAISE EXCEPTION 'Cannot bound learned_geo.country to varchar(8)';
  END IF;
  IF EXISTS (SELECT 1 FROM learned_geo WHERE char_length(region) > 255) THEN
    RAISE EXCEPTION 'Cannot bound learned_geo.region to varchar(255)';
  END IF;
  IF EXISTS (SELECT 1 FROM learned_geo WHERE char_length(city) > 255) THEN
    RAISE EXCEPTION 'Cannot bound learned_geo.city to varchar(255)';
  END IF;
  IF EXISTS (SELECT 1 FROM learned_geo WHERE char_length(district) > 255) THEN
    RAISE EXCEPTION 'Cannot bound learned_geo.district to varchar(255)';
  END IF;
  IF EXISTS (SELECT 1 FROM learned_geo WHERE char_length(house_number) > 64) THEN
    RAISE EXCEPTION 'Cannot bound learned_geo.house_number to varchar(64)';
  END IF;
  IF EXISTS (SELECT 1 FROM learned_geo WHERE char_length(building) > 128) THEN
    RAISE EXCEPTION 'Cannot bound learned_geo.building to varchar(128)';
  END IF;
  IF EXISTS (SELECT 1 FROM learned_geo WHERE char_length(entity_type) > 64) THEN
    RAISE EXCEPTION 'Cannot bound learned_geo.entity_type to varchar(64)';
  END IF;
  IF EXISTS (SELECT 1 FROM learned_geo WHERE char_length(provider) > 32) THEN
    RAISE EXCEPTION 'Cannot bound learned_geo.provider to varchar(32)';
  END IF;
  IF EXISTS (SELECT 1 FROM learned_geo WHERE char_length(provider_type) > 64) THEN
    RAISE EXCEPTION 'Cannot bound learned_geo.provider_type to varchar(64)';
  END IF;
  IF EXISTS (SELECT 1 FROM subscriptions.mobile_subscriptions WHERE char_length(name) > 120) THEN
    RAISE EXCEPTION 'Cannot bound mobile_subscriptions.name to varchar(120)';
  END IF;
END
$$;

-- Queue values are generated internally and have explicit small domains.
ALTER TABLE crawl_tasks
  ALTER COLUMN crawl_generation TYPE VARCHAR(128) USING crawl_generation::VARCHAR(128),
  ALTER COLUMN type TYPE VARCHAR(64) USING type::VARCHAR(64),
  ALTER COLUMN country TYPE VARCHAR(8) USING country::VARCHAR(8),
  ALTER COLUMN status TYPE VARCHAR(16) USING status::VARCHAR(16),
  ALTER COLUMN locked_by TYPE VARCHAR(200) USING locked_by::VARCHAR(200),
  ALTER COLUMN lock_token TYPE UUID USING lock_token::UUID;

ALTER TABLE crawl_task_runs
  ALTER COLUMN crawl_generation TYPE VARCHAR(128) USING crawl_generation::VARCHAR(128);

-- Cluster ids are application-generated (`property:<short hash>`) and bounded.
ALTER TABLE listing_property_clusters
  ALTER COLUMN cluster_id TYPE VARCHAR(128) USING cluster_id::VARCHAR(128);

-- Learned geography has a mix of bounded metadata and genuinely free-form
-- geocoder text. query_text/canonical_name/street/provider_id remain TEXT.
ALTER TABLE learned_geo
  ALTER COLUMN country TYPE VARCHAR(8) USING country::VARCHAR(8),
  ALTER COLUMN region TYPE VARCHAR(255) USING region::VARCHAR(255),
  ALTER COLUMN city TYPE VARCHAR(255) USING city::VARCHAR(255),
  ALTER COLUMN district TYPE VARCHAR(255) USING district::VARCHAR(255),
  ALTER COLUMN house_number TYPE VARCHAR(64) USING house_number::VARCHAR(64),
  ALTER COLUMN building TYPE VARCHAR(128) USING building::VARCHAR(128),
  ALTER COLUMN entity_type TYPE VARCHAR(64) USING entity_type::VARCHAR(64),
  ALTER COLUMN provider TYPE VARCHAR(32) USING provider::VARCHAR(32),
  ALTER COLUMN provider_type TYPE VARCHAR(64) USING provider_type::VARCHAR(64);

-- Mobile preset names are already normalized to 120 characters in the API.
ALTER TABLE subscriptions.mobile_subscriptions
  ALTER COLUMN name TYPE VARCHAR(120) USING name::VARCHAR(120);

ANALYZE crawl_tasks;
ANALYZE listing_property_clusters;
ANALYZE learned_geo;
