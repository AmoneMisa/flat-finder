-- Latitude/longitude are materialized together with the other STORED listing
-- scalars in migration 024 so fresh deployments rewrite the listings heap only
-- once. This migration owns only the spatial access paths.

-- Bounding-box prefilters use country plus latitude as the leading range and
-- retain longitude in the same compact partial index for the remaining check.
CREATE INDEX IF NOT EXISTS listings_active_country_geo_idx
  ON listings(country, lat, lng)
  WHERE active = TRUE AND lat IS NOT NULL AND lng IS NOT NULL;

CREATE INDEX IF NOT EXISTS listings_active_geo_idx
  ON listings(lat, lng)
  WHERE active = TRUE AND lat IS NOT NULL AND lng IS NOT NULL;

ANALYZE listings;
