-- Ensure listing coordinates have an indexable scalar representation. Existing
-- installations that already own physical lat/lng columns keep them because of
-- IF NOT EXISTS; fresh schemas derive them from the canonical JSONB listing.
ALTER TABLE listings
  ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION
    GENERATED ALWAYS AS (
      CASE WHEN jsonb_typeof(data->'lat') = 'number'
        THEN (data->>'lat')::double precision
        ELSE NULL
      END
    ) STORED,
  ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION
    GENERATED ALWAYS AS (
      CASE WHEN jsonb_typeof(data->'lng') = 'number'
        THEN (data->>'lng')::double precision
        ELSE NULL
      END
    ) STORED;

-- Bounding-box prefilters use country plus latitude as the leading range and
-- retain longitude in the same compact partial index for the remaining check.
CREATE INDEX IF NOT EXISTS listings_active_country_geo_idx
  ON listings(country, lat, lng)
  WHERE active = TRUE AND lat IS NOT NULL AND lng IS NOT NULL;

CREATE INDEX IF NOT EXISTS listings_active_geo_idx
  ON listings(lat, lng)
  WHERE active = TRUE AND lat IS NOT NULL AND lng IS NOT NULL;

ANALYZE listings;
