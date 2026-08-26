import {pool} from './db.js';
import {searchPostgresListings as searchPostgresListingsLegacy} from './postgres-search.js';

const MAX_AGE_DAYS = 21;
const CURSOR_VERSION = 1;

function encodeCursor(value) {
  return Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');
}

function decodeCursor(value) {
  if (!value) return null;
  try {
    const parsed = JSON.parse(Buffer.from(String(value), 'base64url').toString('utf8'));
    return parsed?.v === CURSOR_VERSION ? parsed : null;
  } catch {
    return null;
  }
}

function hasValue(value) {
  return value !== null && value !== undefined && value !== '';
}

function canUseFastFeedPath(filters, searchMatches) {
  if (searchMatches) return false;
  if (filters.includeStats || filters.statsOnly || filters.mapOnly) return false;
  if (filters.customSources?.length) return false;
  if (filters.query || filters.listingId || filters.city || filters.district || filters.metro) return false;
  if (filters.sources?.length) return false;
  if (filters.propertyType && filters.propertyType !== 'any') return false;
  if (filters.dealType && filters.dealType !== 'any') return false;
  if (filters.agency && filters.agency !== 'any') return false;
  if (filters.audience && filters.audience !== 'any') return false;
  if (filters.sort && !['newest', 'oldest'].includes(filters.sort)) return false;

  const numericFilters = [
    'priceMin', 'priceMax', 'priceTolerance', 'roomsMin', 'roomsMax',
    'bedroomsMin', 'bedroomsMax', 'areaMin', 'areaMax', 'metroMaxM',
    'nearbyMaxM', 'pricePerSqmMin', 'pricePerSqmMax', 'floorMin', 'floorMax',
    'totalFloorsMin', 'totalFloorsMax', 'yearMin', 'yearMax',
  ];
  if (numericFilters.some((key) => hasValue(filters[key]))) return false;
  if (filters.priceCurrency || filters.nearbyKind) return false;

  const booleanFilters = [
    'newBuilding', 'dishwasher', 'airConditioner', 'parking', 'internet', 'gas',
    'balcony', 'terrace', 'privateYard', 'pets', 'children', 'roomOnly', 'withPhotos',
  ];
  if (booleanFilters.some((key) => filters[key] === true)) return false;

  return true;
}

function publicVisibility(alias) {
  return [
    `${alias}.active = TRUE`,
    `${alias}.source <> 'custom'`,
    `NOT (${alias}.data @> '{"commercial":true}'::jsonb)`,
    `COALESCE(${alias}.data->>'listingKind', 'propertyOffer') <> 'propertyWanted'`,
    `COALESCE(${alias}.data->>'listingStatus', 'active') NOT IN ('sold', 'rented', 'closed', 'outdated')`,
  ];
}

function buildBaseWhere({countries, maxAgeDays}) {
  const params = [];
  const add = (value) => {
    params.push(value);
    return `$${params.length}`;
  };

  const countryValues = [...new Set((countries || [])
    .map((value) => String(value).toUpperCase())
    .filter(Boolean))];
  const ageDays = maxAgeDays != null && Number(maxAgeDays) > 0
    ? Math.min(Number(maxAgeDays), MAX_AGE_DAYS)
    : MAX_AGE_DAYS;
  const ageParam = add(ageDays);
  const countryParam = countryValues.length ? add(countryValues) : null;

  const where = [
    ...publicVisibility('l'),
    `(l.created_at IS NULL OR l.created_at >= NOW() - (${ageParam}::double precision * INTERVAL '1 day'))`,
  ];
  if (countryParam) where.push(`l.country = ANY(${countryParam}::text[])`);

  const newerWhere = [
    ...publicVisibility('newer'),
    `newer.dedupe_key = l.dedupe_key`,
    `(newer.created_at IS NULL OR newer.created_at >= NOW() - (${ageParam}::double precision * INTERVAL '1 day'))`,
  ];
  if (countryParam) newerWhere.push(`newer.country = ANY(${countryParam}::text[])`);

  newerWhere.push(`(
    (l.created_at IS NULL AND (
      newer.created_at IS NOT NULL
      OR (newer.created_at IS NULL AND newer.id > l.id)
    ))
    OR
    (l.created_at IS NOT NULL AND (
      newer.created_at > l.created_at
      OR (newer.created_at = l.created_at AND newer.id > l.id)
    ))
  )`);

  return {
    params,
    where: where.join('\n      AND '),
    newerWhere: newerWhere.join('\n          AND '),
  };
}

async function searchDefaultFeed({filters, countries}) {
  const startedAt = performance.now();
  const {params: baseParams, where, newerWhere} = buildBaseWhere({
    countries,
    maxAgeDays: filters.maxAgeDays,
  });

  const countSql = `
    SELECT COUNT(*)::int AS count
    FROM (
      SELECT l.dedupe_key
      FROM listings l
      WHERE ${where}
      GROUP BY l.dedupe_key
    ) visible_keys
  `;

  const pageParams = [...baseParams];
  const addPage = (value) => {
    pageParams.push(value);
    return `$${pageParams.length}`;
  };

  const sort = filters.sort || 'newest';
  const cursor = decodeCursor(filters.cursor);
  const pageWhere = [];
  let useCursor = false;

  if (cursor && cursor.sort === sort && cursor.id != null) {
    const idParam = addPage(String(cursor.id));
    if (cursor.t) {
      const timeParam = addPage(cursor.t);
      if (sort === 'newest') {
        pageWhere.push(`(l.created_at < ${timeParam}::timestamptz OR (l.created_at = ${timeParam}::timestamptz AND l.id < ${idParam}::bigint) OR l.created_at IS NULL)`);
      } else {
        pageWhere.push(`(l.created_at > ${timeParam}::timestamptz OR (l.created_at = ${timeParam}::timestamptz AND l.id > ${idParam}::bigint) OR l.created_at IS NULL)`);
      }
    } else if (sort === 'newest') {
      pageWhere.push(`l.created_at IS NULL AND l.id < ${idParam}::bigint`);
    } else {
      pageWhere.push(`l.created_at IS NULL AND l.id > ${idParam}::bigint`);
    }
    useCursor = true;
  }

  const limit = Math.max(1, Math.min(Number(filters.limit) || 40, 60));
  const limitParam = addPage(limit);
  const offset = useCursor ? 0 : Math.max(0, Number(filters.offset) || 0);
  const offsetParam = addPage(offset);
  const orderBy = sort === 'oldest'
    ? 'l.created_at ASC NULLS LAST, l.id ASC'
    : 'l.created_at DESC NULLS LAST, l.id DESC';

  const pageSql = `
    SELECT
      l.id AS db_id,
      l.created_at,
      l.data
    FROM listings l
    WHERE ${where}
      AND NOT EXISTS (
        SELECT 1
        FROM listings newer
        WHERE ${newerWhere}
      )
      ${pageWhere.length ? `AND ${pageWhere.join('\n      AND ')}` : ''}
    ORDER BY ${orderBy}
    LIMIT ${limitParam}
    OFFSET ${offsetParam}
  `;

  const [countResult, pageResult] = await Promise.all([
    pool.query(countSql, baseParams),
    pool.query(pageSql, pageParams),
  ]);

  const rows = pageResult.rows;
  const listings = rows.map((row) => row.data || {});
  const count = Number(countResult.rows[0]?.count) || 0;

  let nextCursor = null;
  if (rows.length === limit) {
    const last = rows[rows.length - 1];
    const time = last.created_at instanceof Date
      ? last.created_at.toISOString()
      : (last.created_at ? new Date(last.created_at).toISOString() : null);
    nextCursor = encodeCursor({v: CURSOR_VERSION, sort, t: time, id: String(last.db_id)});
  }

  return {
    count,
    listings,
    nextCursor,
    queryMs: Math.round((performance.now() - startedAt) * 10) / 10,
    searchPath: 'postgres-fast-feed-v2',
  };
}

export async function searchPostgresListings(args) {
  if (canUseFastFeedPath(args.filters, args.searchMatches)) {
    return searchDefaultFeed(args);
  }
  return searchPostgresListingsLegacy(args);
}
