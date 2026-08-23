import { pool } from './db.js';
import { ensureAvailabilitySchema, verifyListingAvailability } from './availability.js';

const ACTIVE_TTL_MS = Math.max(
  60_000,
  Number(process.env.LISTING_AVAILABILITY_TTL_MS) || 6 * 60 * 60_000,
);
const UNKNOWN_TTL_MS = Math.max(
  30_000,
  Number(process.env.LISTING_AVAILABILITY_UNKNOWN_TTL_MS) || 15 * 60_000,
);
const MAX_BATCH = Math.max(
  1,
  Math.min(100, Number(process.env.LISTING_AVAILABILITY_SWEEP_BATCH) || 20),
);

/**
 * Verify stale OLX availability from the isolated worker rather than from a
 * user's /flats-feed request. The API only reads the resulting active/status
 * columns; source network I/O stays out of the request event loop.
 */
export async function verifyDueListingAvailability(limit = MAX_BATCH) {
  await ensureAvailabilitySchema();

  const batch = Math.max(1, Math.min(100, Number(limit) || MAX_BATCH));
  const result = await pool.query(`
    SELECT source, country, source_id
    FROM listings
    WHERE source = 'olx'
      AND active = TRUE
      AND (
        availability_checked_at IS NULL
        OR availability_checked_at < NOW() - (
          CASE
            WHEN availability_status = 'unknown' THEN $1::bigint
            ELSE $2::bigint
          END * INTERVAL '1 millisecond'
        )
      )
    ORDER BY availability_checked_at ASC NULLS FIRST, updated_at DESC
    LIMIT $3
  `, [UNKNOWN_TTL_MS, ACTIVE_TTL_MS, batch]);

  const items = result.rows.map((row) => ({
    source: row.source,
    country: row.country,
    id: String(row.source_id),
  }));

  if (!items.length) return [];
  return verifyListingAvailability(items);
}
