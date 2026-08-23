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
const PRICE_CONFLICT_PCT = Math.max(5, Number(process.env.ANTIFAKE_PRICE_CONFLICT_PCT) || 15);
const CHRONOLOGY_GAP_MS = Math.max(60_000, Number(process.env.ANTIFAKE_CHRONOLOGY_GAP_MINUTES) || 15) * 60_000;
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
      ALTER TABLE listing_photo_hashes
        ADD COLUMN IF NOT EXISTS title TEXT,
        ADD COLUMN IF NOT EXISTS price NUMERIC,
        ADD COLUMN IF NOT EXISTS currency VARCHAR(16),
        ADD COLUMN IF NOT EXISTS by_agency BOOLEAN,
        ADD COLUMN IF NOT EXISTS rooms NUMERIC,
        ADD COLUMN IF NOT EXISTS area_sqm NUMERIC,
        ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ;
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

function finiteNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function parsedTime(value) {
  if (!value) return null;
  const ms = Date.parse(String(value));
  return Number.isFinite(ms) ? ms : null;
}

function textTokens(value) {
  return new Set(
    String(value || '')
      .toLowerCase()
      .replace(/[^\p{L}\p{N}]+/gu, ' ')
      .split(/\s+/)
      .filter((token) => token.length >= 3),
  );
}

function titleSimilarity(a, b) {
  const left = textTokens(a);
  const right = textTokens(b);
  if (!left.size || !right.size) return null;
  let overlap = 0;
  for (const token of left) if (right.has(token)) overlap += 1;
  const union = new Set([...left, ...right]).size;
  return union ? overlap / union : null;
}

/**
 * Score the relationship between two listings that already share an exact photo.
 * Important: this does NOT equate "cheaper" with "fraud". A later agency repost
 * can steal an owner's advert and mark the price up, while a scam clone can copy
 * a legitimate advert and undercut it. Chronology + seller type + price direction
 * are kept as evidence so the caller can flag the copy candidate, not simply the
 * lower-priced listing.
 */
export function scoreCloneRelationship(current, matched) {
  const currentCreated = parsedTime(current?.createdAt);
  const matchedCreated = parsedTime(matched?.created_at ?? matched?.createdAt);
  const chronology = currentCreated != null && matchedCreated != null
    ? currentCreated - matchedCreated > CHRONOLOGY_GAP_MS
      ? 'later_copy_candidate'
      : matchedCreated - currentCreated > CHRONOLOGY_GAP_MS
        ? 'earlier_source_candidate'
        : 'ambiguous'
    : 'unknown';

  const currentAgency = current?.byAgency == null ? null : Boolean(current.byAgency);
  const matchedAgencyRaw = matched?.by_agency ?? matched?.byAgency;
  const matchedAgency = matchedAgencyRaw == null ? null : Boolean(matchedAgencyRaw);
  const sellerRelation = currentAgency == null || matchedAgency == null
    ? 'unknown'
    : currentAgency === matchedAgency
      ? 'same'
      : !matchedAgency && currentAgency
        ? 'owner_to_agency'
        : 'agency_to_owner';

  const currentPrice = finiteNumber(current?.price);
  const matchedPrice = finiteNumber(matched?.price);
  const currentCurrency = String(current?.currency || '').toUpperCase();
  const matchedCurrency = String(matched?.currency || '').toUpperCase();
  const comparablePrice = currentPrice != null && currentPrice > 0 && matchedPrice != null && matchedPrice > 0
    && currentCurrency && currentCurrency === matchedCurrency;
  const priceDeltaPct = comparablePrice ? ((currentPrice - matchedPrice) / matchedPrice) * 100 : null;
  const priceDirection = priceDeltaPct == null
    ? 'unknown'
    : Math.abs(priceDeltaPct) < 8
      ? 'similar'
      : priceDeltaPct > 0
        ? 'higher'
        : 'lower';

  const currentRooms = finiteNumber(current?.rooms);
  const matchedRooms = finiteNumber(matched?.rooms);
  const roomsAgree = currentRooms == null || matchedRooms == null ? null : currentRooms === matchedRooms;
  const currentArea = finiteNumber(current?.areaSqm);
  const matchedArea = finiteNumber(matched?.area_sqm ?? matched?.areaSqm);
  const areaAgree = currentArea == null || matchedArea == null
    ? null
    : Math.abs(currentArea - matchedArea) <= Math.max(2, matchedArea * 0.05);
  const titleScore = titleSimilarity(current?.title, matched?.title);
  const factsAgree = [roomsAgree, areaAgree, titleScore == null ? null : titleScore >= 0.55]
    .filter((value) => value != null);
  const propertyFactsConsistent = factsAgree.length ? factsAgree.filter(Boolean).length >= Math.ceil(factsAgree.length / 2) : false;

  let score = 35; // exact same photo is already meaningful evidence
  if (propertyFactsConsistent) score += 10;
  if (sellerRelation !== 'same' && sellerRelation !== 'unknown') score += 10;
  if (priceDeltaPct != null && Math.abs(priceDeltaPct) >= PRICE_CONFLICT_PCT) score += 20;
  if (chronology === 'later_copy_candidate') score += 15;
  score = Math.min(100, score);

  const currentCopyCandidate = chronology === 'later_copy_candidate' && score >= 60;
  const matchedCopyCandidate = chronology === 'earlier_source_candidate' && score >= 60;

  let reason = 'duplicate_listing';
  if (currentCopyCandidate && sellerRelation === 'owner_to_agency' && priceDirection === 'higher') {
    reason = 'possible_broker_markup_copy';
  } else if (currentCopyCandidate && priceDirection === 'lower' && priceDeltaPct != null && Math.abs(priceDeltaPct) >= PRICE_CONFLICT_PCT) {
    reason = 'possible_low_price_copy';
  } else if (currentCopyCandidate && sellerRelation !== 'same' && sellerRelation !== 'unknown') {
    reason = 'possible_republished_copy';
  } else if (matchedCopyCandidate) {
    reason = 'matched_listing_may_be_copy';
  } else if (priceDeltaPct != null && Math.abs(priceDeltaPct) >= PRICE_CONFLICT_PCT) {
    reason = 'conflicting_duplicate_price';
  }

  return {
    score,
    reason,
    chronology,
    sellerRelation,
    priceDirection,
    priceDeltaPct: priceDeltaPct == null ? null : Math.round(priceDeltaPct * 10) / 10,
    propertyFactsConsistent,
    titleSimilarity: titleScore == null ? null : Math.round(titleScore * 100) / 100,
    currentCopyCandidate,
    matchedCopyCandidate,
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
        `SELECT source, country, source_id, city, photo_url,
                title, price, currency, by_agency, rooms, area_sqm, created_at,
                first_seen_at, last_seen_at
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
          relation: scoreCloneRelationship(listing, row),
        });
      }

      await pool.query(
        `INSERT INTO listing_photo_hashes
          (hash, source, country, source_id, city, photo_url,
           title, price, currency, by_agency, rooms, area_sqm, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
         ON CONFLICT (hash, source, country, source_id, photo_url)
         DO UPDATE SET
           city = EXCLUDED.city,
           title = EXCLUDED.title,
           price = EXCLUDED.price,
           currency = EXCLUDED.currency,
           by_agency = EXCLUDED.by_agency,
           rooms = EXCLUDED.rooms,
           area_sqm = EXCLUDED.area_sqm,
           created_at = COALESCE(EXCLUDED.created_at, listing_photo_hashes.created_at),
           last_seen_at = NOW()`,
        [
          hash,
          identity.source,
          identity.country,
          identity.sourceId,
          identity.city || null,
          url,
          listing.title || null,
          finiteNumber(listing.price),
          String(listing.currency || '').toUpperCase() || null,
          listing.byAgency == null ? null : Boolean(listing.byAgency),
          finiteNumber(listing.rooms),
          finiteNumber(listing.areaSqm),
          listing.createdAt || null,
        ],
      );
    } catch (error) {
      console.warn(`[flats:antifake] ${identity.source}:${identity.sourceId} image skipped: ${error.message}`);
    }
  }

  const uniqueMatches = [...new Map(matches.map((match) => [
    `${match.hash}:${match.matchedSource}:${match.matchedCountry}:${match.matchedListingId}`,
    match,
  ])).values()];

  const grouped = new Map();
  for (const match of uniqueMatches) {
    const key = `${match.matchedSource}:${match.matchedCountry}:${match.matchedListingId}`;
    const current = grouped.get(key) || {
      matchedSource: match.matchedSource,
      matchedCountry: match.matchedCountry,
      matchedListingId: match.matchedListingId,
      matchedCity: match.matchedCity,
      matchedPhotoCount: 0,
      crossCountry: false,
      crossCity: false,
      relation: match.relation,
    };
    current.matchedPhotoCount += 1;
    current.crossCountry ||= match.crossCountry;
    current.crossCity ||= match.crossCity;
    // More matching photos strengthen the same relationship without changing
    // its direction. Cap so a 20-photo advert cannot swamp every other signal.
    current.relation = {
      ...current.relation,
      score: Math.min(100, current.relation.score + Math.min(20, (current.matchedPhotoCount - 1) * 8)),
    };
    grouped.set(key, current);
  }
  const cloneMatches = [...grouped.values()];

  const crossCountry = uniqueMatches.some((match) => match.crossCountry);
  const crossCity = uniqueMatches.some((match) => match.crossCity);
  const currentCopyCandidate = cloneMatches.some((match) => match.relation.currentCopyCandidate && match.relation.score >= 70);
  const matchedCopyCandidate = cloneMatches.some((match) => match.relation.matchedCopyCandidate && match.relation.score >= 70);
  const conflictingClone = cloneMatches.some((match) =>
    match.relation.score >= 65 &&
    (match.relation.priceDirection === 'higher' || match.relation.priceDirection === 'lower' || match.relation.sellerRelation !== 'same'),
  );

  const risk = crossCountry
    ? 'very_high'
    : crossCity || currentCopyCandidate
      ? 'high'
      : uniqueMatches.length
        ? 'medium'
        : 'none';

  return {
    exactDuplicatePhoto: uniqueMatches.length > 0,
    suspectedClone: currentCopyCandidate,
    matchedListingMayBeClone: matchedCopyCandidate,
    conflictingClone,
    risk,
    hashes: hashes.map(({ id, hash }) => ({ id, hash })),
    matches: uniqueMatches,
    cloneMatches,
    checkedAt: new Date().toISOString(),
  };
}
