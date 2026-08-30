-- Materialize scalar values that are repeatedly cast out of the wide JSONB
-- payload during public search. STORED generated columns preserve the current
-- semantics: only JSON numbers participate; strings/unknown values remain NULL.
ALTER TABLE listings
  ADD COLUMN IF NOT EXISTS bedrooms DOUBLE PRECISION
    GENERATED ALWAYS AS (
      CASE WHEN jsonb_typeof(data->'bedrooms') = 'number'
        THEN (data->>'bedrooms')::double precision
        ELSE NULL
      END
    ) STORED,
  ADD COLUMN IF NOT EXISTS floor_number DOUBLE PRECISION
    GENERATED ALWAYS AS (
      CASE WHEN jsonb_typeof(data->'floor') = 'number'
        THEN (data->>'floor')::double precision
        ELSE NULL
      END
    ) STORED,
  ADD COLUMN IF NOT EXISTS total_floors DOUBLE PRECISION
    GENERATED ALWAYS AS (
      CASE WHEN jsonb_typeof(data->'totalFloors') = 'number'
        THEN (data->>'totalFloors')::double precision
        ELSE NULL
      END
    ) STORED,
  ADD COLUMN IF NOT EXISTS building_year DOUBLE PRECISION
    GENERATED ALWAYS AS (
      CASE WHEN jsonb_typeof(data->'buildingYear') = 'number'
        THEN (data->>'buildingYear')::double precision
        ELSE NULL
      END
    ) STORED,
  ADD COLUMN IF NOT EXISTS commission_percent DOUBLE PRECISION
    GENERATED ALWAYS AS (
      CASE WHEN jsonb_typeof(data->'commissionPercent') = 'number'
        THEN (data->>'commissionPercent')::double precision
        ELSE NULL
      END
    ) STORED,
  ADD COLUMN IF NOT EXISTS metro_distance_m DOUBLE PRECISION
    GENERATED ALWAYS AS (
      COALESCE(
        CASE WHEN jsonb_typeof(data->'metroDistanceM') = 'number'
          THEN (data->>'metroDistanceM')::double precision
          ELSE NULL
        END,
        CASE WHEN jsonb_typeof(data->'metroNearby'->0->'distanceM') = 'number'
          THEN (data->'metroNearby'->0->>'distanceM')::double precision
          ELSE NULL
        END
      )
    ) STORED;

-- Country/city are the dominant narrowing dimensions in the listing UI.
-- These indexes remain selective without trying to encode every possible
-- filter combination into a separate composite index.
CREATE INDEX IF NOT EXISTS listings_active_country_city_bedrooms_idx
  ON listings(country, city, bedrooms)
  WHERE active = TRUE AND bedrooms IS NOT NULL;

CREATE INDEX IF NOT EXISTS listings_active_country_city_floor_idx
  ON listings(country, city, floor_number)
  WHERE active = TRUE AND floor_number IS NOT NULL;

CREATE INDEX IF NOT EXISTS listings_active_country_city_total_floors_idx
  ON listings(country, city, total_floors)
  WHERE active = TRUE AND total_floors IS NOT NULL;

CREATE INDEX IF NOT EXISTS listings_active_country_city_building_year_idx
  ON listings(country, city, building_year)
  WHERE active = TRUE AND building_year IS NOT NULL;

CREATE INDEX IF NOT EXISTS listings_active_country_city_commission_idx
  ON listings(country, city, commission_percent)
  WHERE active = TRUE AND commission_percent IS NOT NULL;

CREATE INDEX IF NOT EXISTS listings_active_country_city_metro_distance_idx
  ON listings(country, city, metro_distance_m)
  WHERE active = TRUE AND metro_distance_m IS NOT NULL;

ANALYZE listings;
