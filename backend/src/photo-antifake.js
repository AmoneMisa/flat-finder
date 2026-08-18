import { createHash } from 'node:crypto';
import pg from 'pg';

const { Pool } = pg;

const pool = new Pool({
  host: process.env.PGHOST || 'flat-finder-postgres',
  port: Number(process.env.PGPORT) || 5432,
  database: process.env.POSTGRES_DB || 'flatfinder',
  user: process.env.POSTGRES_USER || 'flatfinder',
  password: process.env.POSTGRES_PASSWORD,
  max: 2,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 10_000,
});

const MAX_IMAGE_BYTES = Math.max(256_000, Number(process.env.ANTIFAKE_MAX_IMAGE_BYTES) || 8 * 1024 * 1024);
const FETCH_TIMEOUT_MS = Math.max(2000, Number(process.env.ANTIFAKE_IMAGE_TIMEOUT_MS) || 8000);
let schemaPromise = null;

function ensureSchema() {
  if (!schemaPromise) {
    schemaPromise = pool.query(`
      CREATE TABLE IF NOT EXISTS listing_photo_hashes (
        hash CHAR(64) NOT NULL,
        source VARCHAR(32) NOT NULL,
        country VARCHAR(8) NOT NULL,
        source_id TEXT NOT NULL,
        city TEXT,
        photo_url TEXT NOT NULL,
        first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY (hash, source, country, source_id, photo_url)
      );
      CREATE INDEX IF NOT EXISTS listing_photo_hashes_hash_idx
        ON listing_photo_hashes(hash);
      CREATE INDEX IF NOT EXISTS listing_photo_hashes_listing_idx
        ON listing_photo_hashes(source, country, source_id);
    `).catch((error) => {
      schemaPromise = null;
      throw error;
    });
  }
  return schemaPromise;
}

async function hashRemoteImage(url) {
  const response = await fetch(url, {
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    headers: { accept: 'image/*' },
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);

  const declared = Number(response.headers.get('content-length')) || 0;
  if (declared > MAX_IMAGE_BYTES) throw new Error('image too large');
  const type = String(response.headers.get('content-type') || '').toLowerCase();
  if (type && !type.startsWith('image/')) throw new Error(`not an image: ${type}`);

  const bytes = Buffer.from(await response.arrayBuffer());
  if (!bytes.length || bytes.length > MAX_IMAGE_BYTES) throw new Error('invalid image size');
  return createHash('sha256').update(bytes).digest('hex');
}

function listingIdentity(listing) {
  return {
    source: String(listing.source || '').toLowerCase(),
    country: String(listing.country || '').toUpperCase(),
    sourceId: String(listing.id),
    city: String(listing.city || ''),
  };
}

export async function detectExactDuplicatePhotos(listing, images) {
  await ensureSchema();
  const identity = listingIdentity(listing);
  const matches = [];
  const hashes = [];

  for (const image of images || []) {
    const url = String(image?.url || image || '');
    if (!/^https?:\/\//i.test(url)) continue;

    try {
      const hash = await hashRemoteImage(url);
      hashes.push({ id: image?.id || null, url, hash });

      const existing = await pool.query(
        `SELECT source, country, source_id, city, photo_url
           FROM listing_photo_hashes
          WHERE hash = $1
            AND NOT (source = $2 AND country = $3 AND source_id = $4)
          ORDER BY last_seen_at DESC
          LIMIT 20`,
        [hash, identity.source, identity.country, identity.sourceId],
      );

      for (const row of existing.rows) {
        const crossCountry = row.country !== identity.country;
        const crossCity = Boolean(identity.city && row.city && row.city.toLowerCase() !== identity.city.toLowerCase());
        matches.push({
          hash,
          photoId: image?.id || null,
          photoUrl: url,
          matchedSource: row.source,
          matchedCountry: row.country,
          matchedListingId: String(row.source_id),
          matchedCity: row.city || null,
          matchedPhotoUrl: row.photo_url,
          crossCountry,
          crossCity,
        });
      }

      await pool.query(
        `INSERT INTO listing_photo_hashes
          (hash, source, country, source_id, city, photo_url)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (hash, source, country, source_id, photo_url)
         DO UPDATE SET city = EXCLUDED.city, last_seen_at = NOW()`,
        [hash, identity.source, identity.country, identity.sourceId, identity.city || null, url],
      );
    } catch (error) {
      console.warn(`[flats:antifake] ${identity.source}:${identity.sourceId} image skipped: ${error.message}`);
    }
  }

  const uniqueMatches = [...new Map(matches.map((match) => [
    `${match.hash}:${match.matchedSource}:${match.matchedCountry}:${match.matchedListingId}`,
    match,
  ])).values()];

  const crossCountry = uniqueMatches.some((match) => match.crossCountry);
  const crossCity = uniqueMatches.some((match) => match.crossCity);
  const risk = crossCountry ? 'very_high' : crossCity ? 'high' : uniqueMatches.length ? 'medium' : 'none';

  return {
    exactDuplicatePhoto: uniqueMatches.length > 0,
    risk,
    hashes: hashes.map(({ id, hash }) => ({ id, hash })),
    matches: uniqueMatches,
    checkedAt: new Date().toISOString(),
  };
}
