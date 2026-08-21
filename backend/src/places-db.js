// Points of interest, stored once per city so coordinate enrichment costs a
// query instead of a network call per listing.
//
// The alternative — asking Overpass/Nominatim what is near each listing — is
// thousands of rate-limited calls per refresh for data that changes about as
// often as a city gets a new metro line. One city-wide pull fills this table,
// and every listing after that is arithmetic over rows already in memory.

import pg from 'pg';

const { Pool } = pg;

const pool = new Pool({
  host: process.env.PGHOST || 'flat-finder-postgres',
  port: Number(process.env.PGPORT) || 5432,
  database: process.env.POSTGRES_DB || 'flatfinder',
  user: process.env.POSTGRES_USER || 'flatfinder',
  password: process.env.POSTGRES_PASSWORD || '',
  max: Number(process.env.PLACES_DB_POOL_MAX) || 4,
  idleTimeoutMillis: 30_000,
});

pool.on('error', (error) => console.error('[places:postgres] idle client error:', error.message));

let initPromise;

export function initPlacesDb() {
  if (initPromise) return initPromise;
  initPromise = (async () => {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS places (
        id BIGSERIAL PRIMARY KEY,
        country VARCHAR(8) NOT NULL,
        city TEXT NOT NULL DEFAULT '',
        kind VARCHAR(32) NOT NULL,
        name TEXT NOT NULL,
        name_ru TEXT,
        lat DOUBLE PRECISION NOT NULL,
        lng DOUBLE PRECISION NOT NULL,
        source VARCHAR(16) NOT NULL,
        external_id TEXT NOT NULL,
        tags JSONB NOT NULL DEFAULT '{}'::jsonb,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT places_identity_unique UNIQUE (country, kind, source, external_id)
      );
    `);
    await pool.query('CREATE INDEX IF NOT EXISTS places_city_kind_idx ON places(country, city, kind);');
    // No PostGIS here, so proximity is a bounding-box prefilter plus haversine.
    await pool.query('CREATE INDEX IF NOT EXISTS places_lat_lng_idx ON places(lat, lng);');
    console.log('[places:postgres] schema ready');
  })().catch((error) => {
    initPromise = undefined;
    throw error;
  });
  return initPromise;
}

const UPSERT_SQL = `
  INSERT INTO places (country, city, kind, name, name_ru, lat, lng, source, external_id, tags, updated_at)
  SELECT input.country, input.city, input.kind, input.name, input.name_ru,
         input.lat, input.lng, input.source, input.external_id, input.tags, NOW()
  FROM jsonb_to_recordset($1::jsonb) AS input (
    country TEXT, city TEXT, kind TEXT, name TEXT, name_ru TEXT,
    lat DOUBLE PRECISION, lng DOUBLE PRECISION, source TEXT, external_id TEXT, tags JSONB
  )
  WHERE input.name <> '' AND input.lat IS NOT NULL AND input.lng IS NOT NULL
  ON CONFLICT (country, kind, source, external_id) DO UPDATE SET
    city = EXCLUDED.city,
    name = EXCLUDED.name,
    name_ru = EXCLUDED.name_ru,
    lat = EXCLUDED.lat,
    lng = EXCLUDED.lng,
    tags = EXCLUDED.tags,
    updated_at = NOW();
`;

export async function upsertPlaces(rows) {
  if (!Array.isArray(rows) || !rows.length) return 0;
  await initPlacesDb();
  let saved = 0;
  for (let offset = 0; offset < rows.length; offset += 500) {
    const batch = rows.slice(offset, offset + 500);
    await pool.query(UPSERT_SQL, [JSON.stringify(batch)]);
    saved += batch.length;
  }
  return saved;
}

/** Every place in a city, for one in-memory pass over a batch of listings. */
export async function loadCityPlaces(country, city) {
  await initPlacesDb();
  const result = await pool.query(
    `SELECT kind, name, name_ru, lat, lng
     FROM places
     WHERE country = $1 AND ($2 = '' OR city = $2);`,
    [String(country || '').toUpperCase(), String(city || '')],
  );
  return result.rows.map((row) => ({
    kind: row.kind,
    name: row.name,
    nameRu: row.name_ru || null,
    lat: Number(row.lat),
    lng: Number(row.lng),
  }));
}

/** When each city was last filled, so a sync can decide whether to run. */
export async function placesFreshness() {
  await initPlacesDb();
  const result = await pool.query(
    `SELECT country, city, kind, COUNT(*)::int AS count, MAX(updated_at) AS updated_at
     FROM places GROUP BY country, city, kind ORDER BY country, city, kind;`,
  );
  return result.rows;
}

export async function closePlacesDb() {
  await pool.end();
}
