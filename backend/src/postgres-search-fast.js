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

async function searchDefaultFeed({filters, countries}) {
  const startedAt = performance.now();
  const {params: baseParams, where} = buildMemberWhere({
    countries,
    maxAgeDays: filters.maxAgeDays,
  });

  const countSql = `
    SELECT COUNT(*)::int AS count
    FROM (
      SELECT m.dedupe_key
      FROM listing_public_feed_members m
      WHERE ${where}
      GROUP BY m.dedupe_key
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
    SELECT p.db_id, p.created_at, l.data
    FROM page p
    JOIN listings l ON l.id = p.db_id
    ORDER BY ${orderBy.replaceAll('d.', 'p.')}
  `;

  const [countTimed, pageTimed] = await Promise.all([
    timedQuery(countSql, baseParams),
    timedQuery(pageSql, pageParams),
  ]);

  const rows = pageTimed.result.rows;
  const listings = rows.map((row) => row.data || {});
  const count = Number(countTimed.result.rows[0]?.count) || 0;

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
    countMs: countTimed.ms,
    pageMs: pageTimed.ms,
    queryMs: Math.round((performance.now() - startedAt) * 10) / 10,
    searchPath: 'postgres-feed-members',
  };
}

export async function searchPostgresListings(args) {
  if (canUseFastFeedPath(args.filters, args.searchMatches)) {
    return searchDefaultFeed(args);
  }
  return searchPostgresListingsLegacy(args);
}
