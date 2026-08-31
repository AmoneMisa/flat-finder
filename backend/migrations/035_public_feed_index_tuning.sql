-- Tune public-feed read-model indexes for the actual DISTINCT ON access pattern.
--
-- The structured feed first filters rows, then chooses the newest row for every
-- dedupe_key using:
--   ORDER BY dedupe_key, created_at DESC NULLS LAST, listing_id DESC
--
-- Indexes that put freshness_at before dedupe_key are useful for a pure age
-- range scan, but they cannot provide this ordering once freshness_at is a range
-- predicate. The default public feed is already lifecycle-bounded, so preserve
-- the equality filter prefixes and then the dedupe ordering; keep freshness_at
-- as an included column for cheap residual filtering.

DROP INDEX IF EXISTS listing_public_feed_members_country_deal_freshness_idx;
DROP INDEX IF EXISTS listing_public_feed_members_country_city_deal_fresh_idx;
DROP INDEX IF EXISTS listing_public_feed_members_country_deal_owner_fresh_idx;
DROP INDEX IF EXISTS listing_public_feed_members_country_source_fresh_idx;
DROP INDEX IF EXISTS listing_public_feed_members_country_deal_price_idx;

CREATE INDEX IF NOT EXISTS listing_public_feed_members_country_deal_dedupe_idx
  ON listing_public_feed_members (
    country,
    deal_type,
    dedupe_key,
    created_at DESC NULLS LAST,
    listing_id DESC
  )
  INCLUDE (freshness_at);

CREATE INDEX IF NOT EXISTS listing_public_feed_members_country_city_deal_dedupe_idx
  ON listing_public_feed_members (
    country,
    city,
    deal_type,
    dedupe_key,
    created_at DESC NULLS LAST,
    listing_id DESC
  )
  INCLUDE (freshness_at);

CREATE INDEX IF NOT EXISTS listing_public_feed_members_country_deal_owner_dedupe_idx
  ON listing_public_feed_members (
    country,
    deal_type,
    by_agency,
    dedupe_key,
    created_at DESC NULLS LAST,
    listing_id DESC
  )
  INCLUDE (freshness_at);

-- FX-aware filtering deliberately uses UPPER(m.currency). Match that expression
-- in the index; an index on the raw currency column cannot service those OR
-- branches reliably when legacy rows differ in case.
CREATE INDEX IF NOT EXISTS listing_public_feed_members_country_deal_currency_price_idx
  ON listing_public_feed_members (
    country,
    deal_type,
    UPPER(currency),
    price,
    listing_id
  )
  WHERE price IS NOT NULL AND currency IS NOT NULL;

ANALYZE listing_public_feed_members;
