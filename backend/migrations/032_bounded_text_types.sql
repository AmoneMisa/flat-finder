-- TEXT and VARCHAR use the same PostgreSQL storage representation. These
-- changes are therefore about schema discipline and rejecting accidental huge
-- values, not about pretending VARCHAR is a storage/performance optimization.
-- Keep prose, URLs, free-form errors, JSON payloads and external identifiers
-- with genuinely unbounded contracts as TEXT.

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
