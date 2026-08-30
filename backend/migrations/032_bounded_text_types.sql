-- TEXT and VARCHAR use the same PostgreSQL storage representation. These
-- changes are therefore about schema discipline and rejecting accidental huge
-- values, not about pretending VARCHAR is a storage/performance optimization.
-- Keep prose, URLs, free-form errors, JSON payloads and external identifiers
-- with genuinely unbounded contracts as TEXT.
--
-- IMPORTANT: explicit casts to VARCHAR(n) can truncate. Validate first and fail
-- loudly instead of silently modifying production data.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM listings WHERE char_length(city) > 255) THEN
    RAISE EXCEPTION 'Cannot bound listings.city to varchar(255): oversized values exist';
  END IF;
  IF EXISTS (SELECT 1 FROM listings WHERE char_length(district) > 255) THEN
    RAISE EXCEPTION 'Cannot bound listings.district to varchar(255): oversized values exist';
  END IF;
  IF EXISTS (SELECT 1 FROM listings WHERE char_length(area) > 255) THEN
    RAISE EXCEPTION 'Cannot bound listings.area to varchar(255): oversized values exist';
  END IF;
  IF EXISTS (SELECT 1 FROM listings WHERE char_length(metro) > 255) THEN
    RAISE EXCEPTION 'Cannot bound listings.metro to varchar(255): oversized values exist';
  END IF;
  IF EXISTS (SELECT 1 FROM listings WHERE char_length(residence_complex) > 512) THEN
    RAISE EXCEPTION 'Cannot bound listings.residence_complex to varchar(512): oversized values exist';
  END IF;

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

  IF EXISTS (SELECT 1 FROM listing_public_feed_members WHERE char_length(country) > 8) THEN
    RAISE EXCEPTION 'Cannot bound listing_public_feed_members.country to varchar(8)';
  END IF;
  IF EXISTS (SELECT 1 FROM listing_location_terms WHERE char_length(term_type) > 64) THEN
    RAISE EXCEPTION 'Cannot bound listing_location_terms.term_type to varchar(64)';
  END IF;
  IF EXISTS (SELECT 1 FROM listing_location_terms WHERE char_length(normalized_name) > 512) THEN
    RAISE EXCEPTION 'Cannot bound listing_location_terms.normalized_name to varchar(512)';
  END IF;
  IF EXISTS (SELECT 1 FROM listing_nearby_places WHERE char_length(kind) > 64) THEN
    RAISE EXCEPTION 'Cannot bound listing_nearby_places.kind to varchar(64)';
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

-- Listing geography is label-sized data, not prose. Keep address itself TEXT.
ALTER TABLE listings
  ALTER COLUMN city TYPE VARCHAR(255) USING city::VARCHAR(255),
  ALTER COLUMN district TYPE VARCHAR(255) USING district::VARCHAR(255),
  ALTER COLUMN area TYPE VARCHAR(255) USING area::VARCHAR(255),
  ALTER COLUMN metro TYPE VARCHAR(255) USING metro::VARCHAR(255),
  ALTER COLUMN residence_complex TYPE VARCHAR(512) USING residence_complex::VARCHAR(512);

-- Queue values are generated internally and have explicit small domains.
ALTER TABLE crawl_tasks
  ALTER COLUMN crawl_generation TYPE VARCHAR(128) USING crawl_generation::VARCHAR(128),
  ALTER COLUMN type TYPE VARCHAR(64) USING type::VARCHAR(64),
  ALTER COLUMN country TYPE VARCHAR(8) USING country::VARCHAR(8),
  ALTER COLUMN status TYPE VARCHAR(16) USING status::VARCHAR(16),
  ALTER COLUMN locked_by TYPE VARCHAR(200) USING locked_by::VARCHAR(200),
  ALTER COLUMN lock_token TYPE UUID USING NULLIF(lock_token, '')::UUID;

ALTER TABLE crawl_task_runs
  ALTER COLUMN crawl_generation TYPE VARCHAR(128) USING crawl_generation::VARCHAR(128);

-- Public-feed and normalized search dimensions are also bounded domains.
ALTER TABLE listing_public_feed_members
  ALTER COLUMN country TYPE VARCHAR(8) USING country::VARCHAR(8);

ALTER TABLE listing_location_terms
  ALTER COLUMN term_type TYPE VARCHAR(64) USING term_type::VARCHAR(64),
  ALTER COLUMN normalized_name TYPE VARCHAR(512) USING normalized_name::VARCHAR(512);

ALTER TABLE listing_nearby_places
  ALTER COLUMN kind TYPE VARCHAR(64) USING kind::VARCHAR(64);

ALTER TABLE listing_property_clusters
  ALTER COLUMN cluster_id TYPE VARCHAR(128) USING cluster_id::VARCHAR(128);

-- Learned geography has a mix of bounded metadata and genuinely free-form
-- geocoder text. query_text/canonical_name/street remain TEXT intentionally.
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

ANALYZE listings;
ANALYZE crawl_tasks;
ANALYZE listing_location_terms;
ANALYZE listing_nearby_places;
