-- Use bounded VARCHAR for fields whose application/domain semantics have a
-- practical maximum length. This is a schema/data-quality constraint, not a
-- PostgreSQL storage-speed optimization: TEXT and VARCHAR use the same varlena
-- representation. Keep free-form text, URLs, source/provider IDs, keys and
-- errors as TEXT so ingestion never truncates externally-owned identifiers or
-- content.
--
-- PostgreSQL rejects this migration if an existing value exceeds a declared
-- bound; no value is silently truncated.

-- Public listings: geographic labels and ISO-like currency codes are bounded;
-- title/description/address/source_id remain free-form TEXT.
ALTER TABLE listings
  ALTER COLUMN city TYPE VARCHAR(160) USING city::VARCHAR(160),
  ALTER COLUMN district TYPE VARCHAR(160) USING district::VARCHAR(160),
  ALTER COLUMN area TYPE VARCHAR(160) USING area::VARCHAR(160),
  ALTER COLUMN metro TYPE VARCHAR(160) USING metro::VARCHAR(160),
  ALTER COLUMN residence_complex TYPE VARCHAR(240) USING residence_complex::VARCHAR(240),
  ALTER COLUMN currency TYPE VARCHAR(8) USING currency::VARCHAR(8);

ALTER TABLE listing_public_feed_members
  ALTER COLUMN country TYPE VARCHAR(8) USING country::VARCHAR(8);

-- Crawl queue: task type/status/worker identity are application-controlled.
-- task_key and crawl_generation remain TEXT because they compose arbitrary
-- source/channel/city identity fragments.
ALTER TABLE crawl_tasks
  ALTER COLUMN type TYPE VARCHAR(64) USING type::VARCHAR(64),
  ALTER COLUMN country TYPE VARCHAR(8) USING country::VARCHAR(8),
  ALTER COLUMN status TYPE VARCHAR(16) USING status::VARCHAR(16),
  ALTER COLUMN locked_by TYPE VARCHAR(200) USING locked_by::VARCHAR(200),
  ALTER COLUMN lock_token TYPE UUID USING NULLIF(lock_token, '')::UUID;

-- Place labels are human-readable names rather than free-form descriptions.
-- external_id remains TEXT because its format is owned by the upstream source.
ALTER TABLE places
  ALTER COLUMN city TYPE VARCHAR(160) USING city::VARCHAR(160),
  ALTER COLUMN name TYPE VARCHAR(255) USING name::VARCHAR(255),
  ALTER COLUMN name_ru TYPE VARCHAR(255) USING name_ru::VARCHAR(255);

-- Learned geocoder metadata. lookup_key/query_text/provider_id stay TEXT; the
-- provider owns provider_id and may change its format independently of us.
ALTER TABLE learned_geo
  ALTER COLUMN country TYPE VARCHAR(8) USING country::VARCHAR(8),
  ALTER COLUMN region TYPE VARCHAR(160) USING region::VARCHAR(160),
  ALTER COLUMN city TYPE VARCHAR(160) USING city::VARCHAR(160),
  ALTER COLUMN district TYPE VARCHAR(160) USING district::VARCHAR(160),
  ALTER COLUMN street TYPE VARCHAR(240) USING street::VARCHAR(240),
  ALTER COLUMN house_number TYPE VARCHAR(64) USING house_number::VARCHAR(64),
  ALTER COLUMN building TYPE VARCHAR(160) USING building::VARCHAR(160),
  ALTER COLUMN entity_type TYPE VARCHAR(64) USING entity_type::VARCHAR(64),
  ALTER COLUMN canonical_name TYPE VARCHAR(255) USING canonical_name::VARCHAR(255),
  ALTER COLUMN provider TYPE VARCHAR(64) USING provider::VARCHAR(64),
  ALTER COLUMN provider_type TYPE VARCHAR(64) USING provider_type::VARCHAR(64);

-- Anti-fake/property identity. photo_url/source_id/title remain TEXT.
ALTER TABLE listing_photo_hashes
  ALTER COLUMN city TYPE VARCHAR(160) USING city::VARCHAR(160),
  ALTER COLUMN district TYPE VARCHAR(160) USING district::VARCHAR(160),
  ALTER COLUMN metro TYPE VARCHAR(160) USING metro::VARCHAR(160),
  ALTER COLUMN residence_complex TYPE VARCHAR(240) USING residence_complex::VARCHAR(240),
  ALTER COLUMN currency TYPE VARCHAR(8) USING currency::VARCHAR(8);

ALTER TABLE listing_property_clusters
  ALTER COLUMN cluster_id TYPE VARCHAR(128) USING cluster_id::VARCHAR(128);

-- Normalized search relations contain controlled entity kinds and display
-- labels; they are not arbitrary listing descriptions.
ALTER TABLE listing_location_terms
  ALTER COLUMN term_type TYPE VARCHAR(64) USING term_type::VARCHAR(64),
  ALTER COLUMN normalized_name TYPE VARCHAR(255) USING normalized_name::VARCHAR(255);

ALTER TABLE listing_nearby_places
  ALTER COLUMN kind TYPE VARCHAR(64) USING kind::VARCHAR(64);

-- Mobile preset names are normalized to 120 characters by the API. Delivery
-- item_key and push_token stay TEXT because they may contain provider-owned IDs.
ALTER TABLE subscriptions.mobile_subscriptions
  ALTER COLUMN name TYPE VARCHAR(120) USING name::VARCHAR(120);

-- hiring-db historically owns its schema at runtime. If the tables already
-- exist, tighten the short columns here; fresh installs get the same types from
-- hiring-db.js after this migration.
DO $$
BEGIN
  IF to_regclass('public.hiring_candidates') IS NOT NULL THEN
    ALTER TABLE hiring_candidates
      ALTER COLUMN source_handle TYPE VARCHAR(255) USING source_handle::VARCHAR(255),
      ALTER COLUMN name TYPE VARCHAR(200) USING name::VARCHAR(200),
      ALTER COLUMN role TYPE VARCHAR(200) USING role::VARCHAR(200),
      ALTER COLUMN city TYPE VARCHAR(160) USING city::VARCHAR(160),
      ALTER COLUMN district TYPE VARCHAR(160) USING district::VARCHAR(160);
  END IF;

  IF to_regclass('public.hiring_source_runs') IS NOT NULL THEN
    ALTER TABLE hiring_source_runs
      ALTER COLUMN handle TYPE VARCHAR(255) USING handle::VARCHAR(255);
  END IF;
END
$$;

ANALYZE listings;
ANALYZE listing_public_feed_members;
ANALYZE crawl_tasks;
ANALYZE places;
ANALYZE learned_geo;
ANALYZE listing_photo_hashes;
ANALYZE listing_property_clusters;
ANALYZE listing_location_terms;
ANALYZE listing_nearby_places;
ANALYZE subscriptions.mobile_subscriptions;
