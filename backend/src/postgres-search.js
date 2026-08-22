import { pool } from './db.js';

const MAX_AGE_DAYS = 21;
const CURSOR_VERSION = 1;

function safeRateEntries(rates) {
  return Object.entries(rates || {})
    .map(([currency, rate]) => [String(currency).toUpperCase(), Number(rate)])
    .filter(([currency, rate]) => /^[A-Z]{3}$/.test(currency) && Number.isFinite(rate) && rate > 0);
}

function priceToUsd(value, currency, rates) {
  if (value == null) return null;
  const rate = Number(rates?.[String(currency || '').toUpperCase()]);
  return Number.isFinite(rate) && rate > 0 ? Number(value) / rate : null;
}

function jsonNumber(column, key) {
  return `CASE WHEN jsonb_typeof(${column}->'${key}') = 'number' THEN (${column}->>'${key}')::double precision ELSE NULL END`;
}

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

function normalizeMatchRows(searchMatches) {
  if (!searchMatches?.rank?.size) return [];
  const rows = [];
  for (const [key, rank] of searchMatches.rank) {
    const parts = String(key).split(':');
    if (parts.length < 3) continue;
    const source = parts.shift();
    const country = parts.shift();
    const sourceId = parts.join(':');
    if (!source || !country || !sourceId) continue;
    rows.push({ source, country, source_id: sourceId, rank: Number(rank) || 0 });
  }
  return rows;
}

function buildSearchContext({ filters, countries, rates, searchMatches }) {
  const params = [];
  const add = (value) => {
    params.push(value);
    return `$${params.length}`;
  };

  const matchRows = normalizeMatchRows(searchMatches);
  const elasticsearchAuthoritative = searchMatches != null;
  let from = 'FROM listings l';
  let rankSelect = 'NULL::integer AS search_rank';
  if (matchRows.length) {
    const p = add(JSON.stringify(matchRows));
    from += `\nJOIN jsonb_to_recordset(${p}::jsonb) AS m(source text, country text, source_id text, rank integer)\n  ON m.source = l.source AND m.country = l.country AND m.source_id = l.source_id`;
    rankSelect = 'm.rank AS search_rank';
  }

  const where = ['l.active = TRUE'];
  if (elasticsearchAuthoritative && matchRows.length === 0) where.push('FALSE');

  const countryValues = [...new Set((countries || []).map((v) => String(v).toUpperCase()).filter(Boolean))];
  if (countryValues.length) {
    where.push(`l.country = ANY(${add(countryValues)}::text[])`);
  }

  if (filters.sources?.length) {
    where.push(`l.source = ANY(${add(filters.sources.map((v) => String(v).toLowerCase()))}::text[])`);
  }

  if (filters.listingId) {
    where.push(`l.source_id = ${add(String(filters.listingId))}`);
  }

  // Same semantics as normalize.applyFilters(): commercial listings never
  // enter the housing feed, while a missing flag is treated as non-commercial.
  where.push(`NOT (l.data @> '{"commercial":true}'::jsonb)`);

  const ageDays = filters.maxAgeDays != null && filters.maxAgeDays > 0
    ? Math.min(Number(filters.maxAgeDays), MAX_AGE_DAYS)
    : MAX_AGE_DAYS;
  where.push(`(l.created_at IS NULL OR l.created_at >= NOW() - (${add(ageDays)}::double precision * INTERVAL '1 day'))`);

  if (filters.propertyType && filters.propertyType !== 'any') {
    where.push(`l.property_type = ${add(filters.propertyType)}`);
  }
  if (filters.dealType && filters.dealType !== 'any') {
    where.push(`l.deal_type = ${add(filters.dealType)}`);
  }
  if (filters.agency === 'agency') where.push('l.by_agency = TRUE');
  if (filters.agency === 'owner') where.push('l.by_agency = FALSE');

  const effectiveMax = filters.priceMax != null
    ? Number(filters.priceMax) + Number(filters.priceTolerance || 0)
    : null;
  const rateEntries = safeRateEntries(rates);
  const convertPrices = rateEntries.length > 0 && filters.priceCurrency;

  let priceUsdExpr = 'l.price';
  if (rateEntries.length) {
    const cases = rateEntries.map(([currency, rate]) => `WHEN '${currency}' THEN l.price / ${rate}`).join(' ');
    priceUsdExpr = `(CASE UPPER(l.currency) ${cases} ELSE NULL END)`;
  }

  if (filters.priceMin != null || effectiveMax != null) {
    if (convertPrices) {
      const minUsd = filters.priceMin != null ? priceToUsd(filters.priceMin, filters.priceCurrency, rates) : null;
      const maxUsd = effectiveMax != null ? priceToUsd(effectiveMax, filters.priceCurrency, rates) : null;
      const branches = [];
      for (const [currency, rate] of rateEntries) {
        const predicates = [`UPPER(l.currency) = '${currency}'`, 'l.price IS NOT NULL'];
        if (minUsd != null) predicates.push(`l.price >= ${add(minUsd * rate)}`);
        if (maxUsd != null) predicates.push(`l.price <= ${add(maxUsd * rate)}`);
        branches.push(`(${predicates.join(' AND ')})`);
      }
      if (branches.length) where.push(`(${branches.join(' OR ')})`);
    } else {
      if (filters.priceMin != null) where.push(`l.price >= ${add(Number(filters.priceMin))}`);
      if (effectiveMax != null) where.push(`l.price <= ${add(Number(effectiveMax))}`);
    }
  }

  if (filters.roomsMin != null) where.push(`l.rooms >= ${add(Number(filters.roomsMin))}`);
  if (filters.roomsMax != null) where.push(`l.rooms <= ${add(Number(filters.roomsMax))}`);
  if (filters.areaMin != null) where.push(`l.area_sqm >= ${add(Number(filters.areaMin))}`);
  if (filters.areaMax != null) where.push(`l.area_sqm <= ${add(Number(filters.areaMax))}`);

  const bedroomsExpr = jsonNumber('l.data', 'bedrooms');
  const floorExpr = jsonNumber('l.data', 'floor');
  const totalFloorsExpr = jsonNumber('l.data', 'totalFloors');
  const buildingYearExpr = jsonNumber('l.data', 'buildingYear');
  if (filters.bedroomsMin != null) where.push(`${bedroomsExpr} >= ${add(Number(filters.bedroomsMin))}`);
  if (filters.bedroomsMax != null) where.push(`${bedroomsExpr} <= ${add(Number(filters.bedroomsMax))}`);
  if (filters.floorMin != null) where.push(`${floorExpr} >= ${add(Number(filters.floorMin))}`);
  if (filters.floorMax != null) where.push(`${floorExpr} <= ${add(Number(filters.floorMax))}`);
  if (filters.totalFloorsMin != null) where.push(`${totalFloorsExpr} >= ${add(Number(filters.totalFloorsMin))}`);
  if (filters.totalFloorsMax != null) where.push(`${totalFloorsExpr} <= ${add(Number(filters.totalFloorsMax))}`);
  if (filters.yearMin != null) where.push(`${buildingYearExpr} >= ${add(Number(filters.yearMin))}`);
  if (filters.yearMax != null) where.push(`${buildingYearExpr} <= ${add(Number(filters.yearMax))}`);

  if (filters.pricePerSqmMin != null || filters.pricePerSqmMax != null) {
    where.push('l.price IS NOT NULL AND l.area_sqm IS NOT NULL AND l.area_sqm > 0');
    const perSqm = convertPrices ? `(${priceUsdExpr} / l.area_sqm)` : '(l.price / l.area_sqm)';
    if (convertPrices) {
      const min = filters.pricePerSqmMin != null ? priceToUsd(filters.pricePerSqmMin, filters.priceCurrency, rates) : null;
      const max = filters.pricePerSqmMax != null ? priceToUsd(filters.pricePerSqmMax, filters.priceCurrency, rates) : null;
      if (min != null) where.push(`${perSqm} >= ${add(min)}`);
      if (max != null) where.push(`${perSqm} <= ${add(max)}`);
    } else {
      if (filters.pricePerSqmMin != null) where.push(`${perSqm} >= ${add(Number(filters.pricePerSqmMin))}`);
      if (filters.pricePerSqmMax != null) where.push(`${perSqm} <= ${add(Number(filters.pricePerSqmMax))}`);
    }
  }

  if (filters.newBuilding === true) where.push(`l.data @> '{"newBuilding":true}'::jsonb`);
  if (filters.audience && filters.audience !== 'any') where.push(`l.data->>'audience' = ${add(filters.audience)}`);
  if (filters.pets === true) where.push(`l.data @> '{"petsAllowed":true}'::jsonb`);
  if (filters.children === true) where.push(`COALESCE(l.data->>'childrenAllowed', '') <> 'false'`);
  if (filters.roomOnly === true) where.push(`l.data @> '{"roomOnly":true}'::jsonb`);

  const booleanFilters = [
    ['dishwasher', 'dishwasher'],
    ['airConditioner', 'airConditioner'],
    ['parking', 'parking'],
    ['internet', 'internet'],
    ['gas', 'gas'],
    ['balcony', 'balcony'],
    ['terrace', 'terrace'],
    ['privateYard', 'privateYard'],
  ];
  for (const [filterName, dataName] of booleanFilters) {
    if (filters[filterName] === true) {
      where.push(`l.data @> '{"${dataName}":true}'::jsonb`);
    }
  }

  if (filters.city) {
    const forms = [...new Set((filters.cityAliases?.length ? filters.cityAliases : [filters.city]).map(String).filter(Boolean))];
    where.push(`l.city = ANY(${add(forms)}::text[])`);
  }
  if (filters.district) where.push(`l.district = ${add(String(filters.district))}`);
  if (filters.metro) where.push(`l.metro = ${add(String(filters.metro))}`);

  if (filters.metroMaxM != null) {
    const metroDistance = `COALESCE(${jsonNumber('l.data', 'metroDistanceM')}, ${jsonNumber("(l.data->'metroNearby'->0)", 'distanceM')})`;
    where.push(`${metroDistance} <= ${add(Number(filters.metroMaxM))}`);
  }

  if (filters.nearbyKind || filters.nearbyMaxM != null) {
    const placeChecks = [];
    if (filters.nearbyKind) placeChecks.push(`LOWER(COALESCE(place->>'kind','')) = ${add(String(filters.nearbyKind).toLowerCase())}`);
    if (filters.nearbyMaxM != null) {
      placeChecks.push(`CASE WHEN jsonb_typeof(place->'distanceM') = 'number' THEN (place->>'distanceM')::double precision ELSE NULL END <= ${add(Number(filters.nearbyMaxM))}`);
    }
    where.push(`EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(l.data->'nearbyPlaces','[]'::jsonb)) AS place WHERE ${placeChecks.length ? placeChecks.join(' AND ') : 'TRUE'})`);
  }

  // Elasticsearch supplies the authoritative match set. This SQL branch is a
  // degraded fallback only, so it deliberately favors correctness over an
  // additional heavyweight text index in PostgreSQL.
  if (filters.query && !elasticsearchAuthoritative) {
    const q = `%${String(filters.query).toLowerCase()}%`;
    const p = add(q);
    where.push(`LOWER(CONCAT_WS(' ', l.title, l.description, l.city, l.district, l.metro, l.data->>'region', l.data->>'microdistrict', l.data->>'residenceComplex', l.data->>'tags')) LIKE ${p}`);
  }

  let orderBy;
  let sort = filters.sort || null;
  if (matchRows.length && !sort) {
    orderBy = 'm.rank ASC, l.created_at DESC NULLS LAST, l.id DESC';
  } else {
    sort = sort || 'newest';
    switch (sort) {
      case 'oldest':
        orderBy = 'l.created_at ASC NULLS LAST, l.id ASC';
        break;
      case 'priceAsc':
        orderBy = `${priceUsdExpr} ASC NULLS LAST, l.id ASC`;
        break;
      case 'priceDesc':
        orderBy = `${priceUsdExpr} DESC NULLS LAST, l.id DESC`;
        break;
      case 'titleAsc':
        orderBy = 'LOWER(l.title) ASC NULLS LAST, l.id ASC';
        break;
      case 'titleDesc':
        orderBy = 'LOWER(l.title) DESC NULLS LAST, l.id DESC';
        break;
      case 'newest':
      default:
        sort = 'newest';
        orderBy = 'l.created_at DESC NULLS LAST, l.id DESC';
        break;
    }
  }

  return {
    params,
    from,
    where,
    rankSelect,
    orderBy,
    sort,
    priceUsdExpr,
    matchRows,
  };
}

export async function initPostgresSearchSchema() {
  const statements = [
    `CREATE INDEX IF NOT EXISTS listings_feed_newest_idx ON listings(country, city, deal_type, created_at DESC, id DESC) WHERE active = TRUE`,
    `CREATE INDEX IF NOT EXISTS listings_feed_price_idx ON listings(country, city, deal_type, currency, price, id) WHERE active = TRUE`,
    `CREATE INDEX IF NOT EXISTS listings_feed_district_idx ON listings(country, city, district, deal_type, created_at DESC, id DESC) WHERE active = TRUE`,
    `CREATE INDEX IF NOT EXISTS listings_feed_rooms_idx ON listings(country, city, deal_type, rooms, created_at DESC, id DESC) WHERE active = TRUE`,
    `CREATE INDEX IF NOT EXISTS listings_feed_area_idx ON listings(country, city, deal_type, area_sqm, created_at DESC, id DESC) WHERE active = TRUE`,
    `CREATE INDEX IF NOT EXISTS listings_feed_title_idx ON listings(country, city, deal_type, LOWER(title), id) WHERE active = TRUE`,
    `CREATE INDEX IF NOT EXISTS listings_active_data_gin_idx ON listings USING GIN(data jsonb_path_ops) WHERE active = TRUE`,
  ];
  for (const sql of statements) await pool.query(sql);
  console.log('[postgres-search] indexes ready');
}

export async function searchPostgresListings({ filters, countries, rates = null, searchMatches = null }) {
  const startedAt = performance.now();
  const context = buildSearchContext({ filters, countries, rates, searchMatches });
  const baseWhere = context.where.join('\n  AND ');
  const baseParams = [...context.params];

  const countSql = `SELECT COUNT(*)::int AS count\n${context.from}\nWHERE ${baseWhere}`;

  const pageParams = [...baseParams];
  const addPage = (value) => {
    pageParams.push(value);
    return `$${pageParams.length}`;
  };

  const cursor = decodeCursor(filters.cursor);
  const pageWhere = [...context.where];
  let useCursor = false;
  if (cursor && cursor.sort === context.sort && ['newest', 'oldest'].includes(context.sort) && cursor.id != null) {
    const idParam = addPage(String(cursor.id));
    if (cursor.t) {
      const timeParam = addPage(cursor.t);
      if (context.sort === 'newest') {
        pageWhere.push(`(l.created_at < ${timeParam}::timestamptz OR (l.created_at = ${timeParam}::timestamptz AND l.id < ${idParam}::bigint) OR l.created_at IS NULL)`);
      } else {
        pageWhere.push(`(l.created_at > ${timeParam}::timestamptz OR (l.created_at = ${timeParam}::timestamptz AND l.id > ${idParam}::bigint) OR l.created_at IS NULL)`);
      }
    } else if (context.sort === 'newest') {
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

  const pageSql = `
    SELECT
      l.id AS db_id,
      l.created_at,
      l.price,
      l.currency,
      l.title,
      l.data,
      ${context.rankSelect}
    ${context.from}
    WHERE ${pageWhere.join('\n      AND ')}
    ORDER BY ${context.orderBy}
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
  if (rows.length === limit && ['newest', 'oldest'].includes(context.sort)) {
    const last = rows[rows.length - 1];
    const time = last.created_at instanceof Date
      ? last.created_at.toISOString()
      : (last.created_at ? new Date(last.created_at).toISOString() : null);
    nextCursor = encodeCursor({ v: CURSOR_VERSION, sort: context.sort, t: time, id: String(last.db_id) });
  }

  return {
    count,
    listings,
    nextCursor,
    queryMs: Math.round((performance.now() - startedAt) * 10) / 10,
    searchPath: searchMatches ? 'postgres+elasticsearch' : 'postgres',
  };
}
