import { pool } from './db.js';
import { COUNTRIES } from './countries.js';

const OLX_FETCHER_URL = String(process.env.OLX_FETCHER_URL || '').replace(/\/$/, '');
// OLX rental inventory churns quickly. Six hours was long enough for a large
// fraction of a filtered result page to disappear before we revisited it.
// Keep the cache short enough for user-facing results while still avoiding a
// source request on every page load (all checks stay in the worker).
const ACTIVE_TTL_MS = Math.max(60_000, Number(process.env.LISTING_AVAILABILITY_TTL_MS) || 30 * 60_000);
const UNKNOWN_TTL_MS = Math.max(30_000, Number(process.env.LISTING_AVAILABILITY_UNKNOWN_TTL_MS) || 10 * 60_000);
const REQUEST_TIMEOUT_MS = Math.max(3_000, Number(process.env.LISTING_AVAILABILITY_REQUEST_TIMEOUT_MS) || 18_000);
const CONCURRENCY = Math.max(1, Math.min(6, Number(process.env.LISTING_AVAILABILITY_CONCURRENCY) || 4));
const MAX_BATCH = 100;

const inFlight = new Map();
let schemaPromise = null;

function listingKey(source, country, id) {
  return `${String(source || '').toLowerCase()}:${String(country || '').toUpperCase()}:${String(id || '')}`;
}

function normalizeRequests(items) {
  const unique = new Map();
  for (const item of Array.isArray(items) ? items : []) {
    const source = String(item?.source || '').trim().toLowerCase();
    const country = String(item?.country || '').trim().toUpperCase();
    const id = String(item?.id ?? '').trim();
    if (!source || !country || !id) continue;
    if (source !== 'olx') continue;
    if (!COUNTRIES[country]) continue;
    unique.set(listingKey(source, country, id), { source, country, id });
    if (unique.size >= MAX_BATCH) break;
  }
  return [...unique.values()];
}

function olxPublicId(url) {
  const value = String(url || '').trim();
  if (!value) return null;
  const match = value.match(/-ID([a-z0-9]+)\.html(?:[?#].*)?$/i);
  return match?.[1] || null;
}

export async function initAvailabilitySchema() {
  await pool.query(`
    ALTER TABLE listings
      ADD COLUMN IF NOT EXISTS availability_checked_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS availability_status VARCHAR(16),
      ADD COLUMN IF NOT EXISTS availability_reason TEXT
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS listings_availability_due_idx
      ON listings(active, availability_checked_at)
  `);
  console.log('[availability] schema ready');
}

export function ensureAvailabilitySchema() {
  if (!schemaPromise) {
    schemaPromise = initAvailabilitySchema().catch((error) => {
      schemaPromise = null;
      throw error;
    });
  }
  return schemaPromise;
}

async function loadRows(items) {
  if (!items.length) return [];
  const result = await pool.query(`
    SELECT
      l.source,
      l.country,
      l.source_id,
      l.active,
      l.availability_checked_at,
      l.availability_status,
      l.availability_reason,
      l.data
    FROM listings l
    JOIN jsonb_to_recordset($1::jsonb)
      AS requested(source text, country text, source_id text)
      ON requested.source = l.source
      AND requested.country = l.country
      AND requested.source_id = l.source_id
  `, [JSON.stringify(items.map((item) => ({
    source: item.source,
    country: item.country,
    source_id: item.id,
  })))]);
  return result.rows;
}

function cachedResult(row) {
  const checkedAt = row.availability_checked_at
    ? new Date(row.availability_checked_at).toISOString()
    : null;

  if (row.active === false) {
    return {
      source: row.source,
      country: row.country,
      id: String(row.source_id),
      status: 'inactive',
      reason: row.availability_reason || 'database_inactive',
      checkedAt,
      cached: true,
    };
  }

  if (!checkedAt || !row.availability_status) return null;
  const age = Date.now() - Date.parse(checkedAt);
  const ttl = row.availability_status === 'unknown' ? UNKNOWN_TTL_MS : ACTIVE_TTL_MS;
  if (!Number.isFinite(age) || age < 0 || age >= ttl) return null;

  return {
    source: row.source,
    country: row.country,
    id: String(row.source_id),
    status: row.availability_status,
    reason: row.availability_reason || null,
    checkedAt,
    cached: true,
  };
}

export async function recordListingAvailability({ source, country, id, status, reason = null }) {
  await ensureAvailabilitySchema();

  if (!['active', 'inactive', 'unknown'].includes(status)) {
    throw new Error(`Unsupported availability status: ${status}`);
  }

  const result = await pool.query(`
    UPDATE listings
    SET
      availability_checked_at = NOW(),
      availability_status = $4::varchar(16),
      availability_reason = $5,
      active = CASE
        WHEN $4::varchar(16) = 'inactive' THEN FALSE
        WHEN $4::varchar(16) = 'active' THEN TRUE
        ELSE active
      END,
      missed_runs = CASE WHEN $4::varchar(16) = 'active' THEN 0 ELSE missed_runs END,
      updated_at = CASE WHEN $4::varchar(16) IN ('active', 'inactive') THEN NOW() ELSE updated_at END
    WHERE source = $1 AND country = $2 AND source_id = $3
    RETURNING active, availability_checked_at
  `, [source, country, id, status, reason]);

  const row = result.rows[0];
  return {
    active: row?.active ?? null,
    checkedAt: row?.availability_checked_at
      ? new Date(row.availability_checked_at).toISOString()
      : new Date().toISOString(),
  };
}

async function fetchOlxAvailability(row) {
  if (!OLX_FETCHER_URL) {
    return { status: 'unknown', reason: 'olx_fetcher_disabled' };
  }

  const url = String(row.data?.url || '').trim();
  if (!/^https:\/\//i.test(url)) {
    return { status: 'unknown', reason: 'missing_source_url' };
  }

  const endpoint = `${OLX_FETCHER_URL}/olx/check?country=${encodeURIComponent(row.country)}`;
  const probeId = olxPublicId(url) || String(row.source_id);
  let response;
  try {
    response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ id: probeId, url }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
  } catch (error) {
    return {
      status: 'unknown',
      reason: error?.name === 'TimeoutError' ? 'sidecar_timeout' : 'sidecar_fetch_error',
    };
  }

  if (!response.ok) {
    return { status: 'unknown', reason: `sidecar_http_${response.status}` };
  }

  let body;
  try {
    body = await response.json();
  } catch {
    return { status: 'unknown', reason: 'sidecar_invalid_json' };
  }

  const status = ['active', 'inactive', 'unknown'].includes(body?.status)
    ? body.status
    : 'unknown';
  return {
    status,
    reason: body?.reason ? String(body.reason) : null,
  };
}

async function verifyRow(row) {
  const cached = cachedResult(row);
  if (cached) return cached;

  const key = listingKey(row.source, row.country, row.source_id);
  const existing = inFlight.get(key);
  if (existing) return existing;

  const promise = (async () => {
    let result;
    if (row.source === 'olx') {
      result = await fetchOlxAvailability(row);
    } else {
      result = { status: 'unknown', reason: 'unsupported_source' };
    }

    const recorded = await recordListingAvailability({
      source: row.source,
      country: row.country,
      id: String(row.source_id),
      status: result.status,
      reason: result.reason,
    });

    return {
      source: row.source,
      country: row.country,
      id: String(row.source_id),
      status: result.status,
      reason: result.reason,
      checkedAt: recorded.checkedAt,
      cached: false,
    };
  })().finally(() => inFlight.delete(key));

  inFlight.set(key, promise);
  return promise;
}

async function mapConcurrent(items, fn) {
  const results = new Array(items.length);
  let cursor = 0;

  async function worker() {
    while (true) {
      const index = cursor++;
      if (index >= items.length) return;
      results[index] = await fn(items[index]);
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(CONCURRENCY, items.length) }, () => worker()),
  );
  return results;
}

export async function verifyListingAvailability(items) {
  await ensureAvailabilitySchema();

  const requested = normalizeRequests(items);
  if (!requested.length) return [];

  const rows = await loadRows(requested);
  const byKey = new Map(rows.map((row) => [
    listingKey(row.source, row.country, row.source_id),
    row,
  ]));

  const present = requested
    .map((item) => byKey.get(listingKey(item.source, item.country, item.id)))
    .filter(Boolean);

  return mapConcurrent(present, verifyRow);
}
