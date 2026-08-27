import {pool} from './db.js';
import {searchPostgresListings as searchPostgresListingsLegacy} from './postgres-search.js';

const MAX_AGE_DAYS = 14;
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

const NUMERIC_FILTERS = [
  'priceMin', 'priceMax', 'priceTolerance', 'roomsMin', 'roomsMax',
  'bedroomsMin', 'bedroomsMax', 'areaMin', 'areaMax', 'metroMaxM',
  'nearbyMaxM', 'pricePerSqmMin', 'pricePerSqmMax', 'floorMin', 'floorMax',
  'totalFloorsMin', 'totalFloorsMax', 'yearMin', 'yearMax',
];

const BOOLEAN_FILTERS = [
  'newBuilding', 'dishwasher', 'airConditioner', 'parking', 'internet', 'gas',
  'balcony', 'terrace', 'privateYard', 'pets', 'children', 'roomOnly', 'withPhotos',
];

function hasSecondaryFilters(filters) {
  if (filters.customSources?.length || filters.query || filters.city || filters.district || filters.metro) return true;
  if (filters.propertyType && filters.propertyType !== 'any') return true;
  if (filters.dealType && filters.dealType !== 'any') return true;
  if (filters.agency && filters.agency !== 'any') return true;
  if (filters.audience && filters.audience !== 'any') return true;
  if (NUMERIC_FILTERS.some((key) => hasValue(filters[key]))) return true;
  if (filters.priceCurrency || filters.nearbyKind) return true;
  return BOOLEAN_FILTERS.some((key) => filters[key] === true);
}

export function canUseFastListingPath(filters, countries, searchMatches) {
  if (!filters.listingId || searchMatches) return false;
  if (filters.includeStats || filters.statsOnly || filters.mapOnly) return false;
  if (filters.sources?.length !== 1 || countries?.length !== 1) return false;
  return !hasSecondaryFilters(filters);
}

function canUseFastFeedPath(filters, searchMatches) {
  if (searchMatches) return false;
  if (filters.includeStats || filters.statsOnly || filters.mapOnly) return false;
  if (filters.listingId) return false;
  if (filters.sources?.length) return false;
  if (filters.sort && !['newest', 'oldest'].includes(filters.sort)) return false;
  return !hasSecondaryFilters(filters);
}

function buildMemberWhere({countries, maxAgeDays}) {
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

  const where = [
    `m.freshness_at >= NOW() - (${add(ageDays)}::double precision * INTERVAL '1 day')`,
  ];
  if (countryValues.length) {
    where.push(`m.country = ANY(${add(countryValues)}::text[])`);
  }

  return {
    params,
    where: where.join('\n      AND '),
  };
}

async function timedQuery(sql, params) {
  const startedAt = performance.now();
  const result = await pool.query(sql, params);
  return {
    result,
    ms: Math.round((performance.now() - startedAt) * 10) / 10,
  };
}

async function searchExactListing({filters, countries}) {
  const startedAt = performance.now();
  const ageDays = filters.maxAgeDays != null && Number(filters.maxAgeDays) > 0
    ? Math.min(Number(filters.maxAgeDays), MAX_AGE_DAYS)
    : MAX_AGE_DAYS;
  const query = await timedQuery(`
    SELECT l.id AS db_id, l.created_at, l.data
    FROM listings l
    WHERE l.source = $1
      AND l.country = $2
      AND l.source_id = $3
      AND l.active = TRUE
      AND COALESCE(l.data->>'listingKind', 'propertyOffer') <> 'propertyWanted'
      AND COALESCE(l.data->>'listingStatus', 'active') NOT IN ('sold', 'rented', 'closed', 'outdated')
      AND NOT (l.data @> '{"commercial":true}'::jsonb)
      AND (l.created_at IS NULL OR l.created_at >= NOW() - ($4::double precision * INTERVAL '1 day'))
    LIMIT 1
  `, [filters.sources[0], countries[0], String(filters.listingId), ageDays]);
  const row = query.result.rows[0];

  return {
    count: row ? 1 : 0,
    listings: row ? [row.data || {}] : [],
    nextCursor: null,
    countMs: 0,
    pageMs: query.ms,
    queryMs: Math.round((performance.now() - startedAt) * 10) / 10,
    searchPath: 'postgres-listing-id',
  };
}

async function searchDefaultFeed({filters, countries}) {
  const startedAt = performance.now();
  const {params: baseParams, where} = buildMemberWhere({
    countries,
    maxAgeDays: filters.maxAgeDays,
  });

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
        pageWhere.push(`(d.created_at < ${timeParam}::timestamptz OR (d.created_at = ${timeParam}::timestamptz AND d.db_id < ${idParam}::bigint) OR d.created_at IS NULL)`);
      } else {
        pageWhere.push(`(d.created_at > ${timeParam}::timestamptz OR (d.created_at = ${timeParam}::timestamptz AND d.db_id > ${idParam}::bigint) OR d.created_at IS NULL)`);
      }
    } else if (sort === 'newest') {
      pageWhere.push(`d.created_at IS NULL AND d.db_id < ${idParam}::bigint`);
    } else {
      pageWhere.push(`d.created_at IS NULL AND d.db_id > ${idParam}::bigint`);
    }
    useCursor = true;
  }

  const limit = Math.max(1, Math.min(Number(filters.limit) || 40, 60));
  const limitParam = addPage(limit);
  const offset = useCursor ? 0 : Math.max(0, Number(filters.offset) || 0);
  const offsetParam = addPage(offset);
  const orderBy = sort === 'oldest'
    ? 'd.created_at ASC NULLS LAST, d.db_id ASC'
    : 'd.created_at DESC NULLS LAST, d.db_id DESC';

  const pageSql = `
    WITH deduped AS MATERIALIZED (
      SELECT DISTINCT ON (m.dedupe_key)
        m.listing_id AS db_id,
        m.created_at
      FROM listing_public_feed_members m
      WHERE ${where}
      ORDER BY m.dedupe_key, m.created_at DESC NULLS LAST, m.listing_id DESC
    ),
    page AS MATERIALIZED (
      SELECT d.db_id, d.created_at
      FROM deduped d
      ${pageWhere.length ? `WHERE ${pageWhere.join('\n        AND ')}` : ''}
      ORDER BY ${orderBy}
      LIMIT ${limitParam}
      OFFSET ${offsetParam}
    )
    SELECT totals.count, p.db_id, p.created_at, l.data
    FROM (SELECT COUNT(*)::int AS count FROM deduped) totals
    LEFT JOIN page p ON TRUE
    LEFT JOIN listings l ON l.id = p.db_id
    ORDER BY ${orderBy.replaceAll('d.', 'p.')}
  `;

  const pageTimed = await timedQuery(pageSql, pageParams);

  const rows = pageTimed.result.rows.filter((row) => row.db_id != null);
  const listings = rows.map((row) => row.data || {});
  const count = Number(pageTimed.result.rows[0]?.count) || 0;

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
    countMs: 0,
    pageMs: pageTimed.ms,
    queryMs: Math.round((performance.now() - startedAt) * 10) / 10,
    searchPath: 'postgres-feed-members',
  };
}

export async function searchPostgresListings(args) {
  if (canUseFastListingPath(args.filters, args.countries, args.searchMatches)) {
    return searchExactListing(args);
  }
  if (canUseFastFeedPath(args.filters, args.searchMatches)) {
    return searchDefaultFeed(args);
  }
  return searchPostgresListingsLegacy(args);
}
