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

  const where = [
    'l.active = TRUE',
    `COALESCE(l.data->>'listingKind', 'propertyOffer') <> 'propertyWanted'`,
    `COALESCE(l.data->>'listingStatus', 'active') NOT IN ('sold', 'rented', 'closed', 'outdated')`,
  ];
  if (elasticsearchAuthoritative && matchRows.length === 0) where.push('FALSE');

  const countryValues = [...new Set((countries || []).map((v) => String(v).toUpperCase()).filter(Boolean))];
  if (countryValues.length) {
    where.push(`l.country = ANY(${add(countryValues)}::text[])`);
  }

  if (filters.sources?.length) {
    where.push(`l.source = ANY(${add(filters.sources.map((v) => String(v).toLowerCase()))}::text[])`);
  }

  const customSources = [...new Set((filters.customSources || []).map(String).filter(Boolean))];
  if (customSources.length) {
    where.push(`(l.source <> 'custom' OR l.data->>'customSourceUrl' = ANY(${add(customSources)}::text[]))`);
  } else {
    where.push(`l.source <> 'custom'`);
  }

  if (filters.listingId) {
    where.push(`l.source_id = ${add(String(filters.listingId))}`);
  }

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
  if (filters.withPhotos === true) {
    where.push(`(
      COALESCE(NULLIF(BTRIM(l.data->>'photo'), ''), '') <> ''
      OR JSONB_ARRAY_LENGTH(CASE WHEN jsonb_typeof(l.data->'photos') = 'array' THEN l.data->'photos' ELSE '[]'::jsonb END) > 0
    )`);
  }

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
    const forms = [...new Set((filters.cityAliases?.length ? filters.cityAliases : [filters.city])
      .map((value) => String(value).toLowerCase())
      .filter(Boolean))];
    where.push(`LOWER(l.city) = ANY(${add(forms)}::text[])`);
  }
  if (filters.district) where.push(`LOWER(l.district) = ${add(String(filters.district).toLowerCase())}`);
  if (filters.metro) where.push(`LOWER(l.metro) = ${add(String(filters.metro).toLowerCase())}`);

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

function olxPhotoSql(alias, index) {
  const photo = `${alias}.data->'photos'->${index}`;
  const raw = `CASE
    WHEN jsonb_typeof(${photo}) = 'string' THEN ${alias}.data->'photos'->>${index}
    WHEN jsonb_typeof(${photo}) = 'object' THEN COALESCE(${photo}->>'link', ${photo}->>'url', ${photo}->>'src', '')
    ELSE ''
  END`;

  return `LOWER(REGEXP_REPLACE(SPLIT_PART(COALESCE(${raw}, ''), '?', 1), ';s=.*$', ''))`;
}

function listingDedupeSql(alias = 'l') {
  const photo0 = olxPhotoSql(alias, 0);
  const photo1 = olxPhotoSql(alias, 1);
  const title = `LOWER(REGEXP_REPLACE(BTRIM(COALESCE(${alias}.title, '')), '\\s+', ' ', 'g'))`;
  const description = `LOWER(REGEXP_REPLACE(BTRIM(COALESCE(${alias}.description, '')), '\\s+', ' ', 'g'))`;
  const telegramPhotoKey = `COALESCE(${alias}.data->>'photoFingerprintKey', '')`;

  return `CASE
    WHEN LOWER(${alias}.source) = 'olx'
      AND LENGTH(${photo0}) >= 24
      AND LENGTH(${photo1}) >= 24
      AND ${photo0} <> ${photo1}
      THEN 'olx:photos:' || MD5(CONCAT_WS('|', UPPER(${alias}.country), ${photo0}, ${photo1}))
    WHEN LOWER(${alias}.source) = 'olx'
      AND LENGTH(${description}) >= 120
      THEN 'olx:content:' || MD5(CONCAT_WS('|',
        UPPER(${alias}.country),
        LOWER(COALESCE(${alias}.city, '')),
        COALESCE(${alias}.deal_type, ''),
        COALESCE(${alias}.property_type, ''),
        COALESCE(${alias}.price::text, ''),
        UPPER(COALESCE(${alias}.currency, '')),
        COALESCE(${alias}.rooms::text, ''),
        COALESCE(ROUND(${alias}.area_sqm::numeric, 1)::text, ''),
        ${title},
        ${description}
      ))
    WHEN LOWER(${alias}.source) = 'telegram'
      AND LENGTH(${telegramPhotoKey}) >= 129
      THEN 'telegram:photos:' || MD5(CONCAT_WS('|',
        UPPER(${alias}.country),
        ${telegramPhotoKey}
      ))
    WHEN LOWER(${alias}.source) = 'telegram'
      AND LENGTH(${description}) >= 40
      THEN 'telegram:content:' || MD5(CONCAT_WS('|',
        UPPER(${alias}.country),
        LOWER(COALESCE(${alias}.city, '')),
        COALESCE(${alias}.deal_type, ''),
        COALESCE(${alias}.property_type, ''),
        COALESCE(${alias}.price::text, ''),
        UPPER(COALESCE(${alias}.currency, '')),
        COALESCE(${alias}.rooms::text, ''),
        COALESCE(ROUND(${alias}.area_sqm::numeric, 1)::text, ''),
        ${title},
        ${description}
      ))
    ELSE CONCAT_WS(':', LOWER(${alias}.source), UPPER(${alias}.country), ${alias}.source_id)
  END`;
}

export async function searchPostgresListings({ filters, countries, rates = null, searchMatches = null }) {
  const startedAt = performance.now();
  const context = buildSearchContext({ filters, countries, rates, searchMatches });
  const baseWhere = context.where.join('\n  AND ');
  const baseParams = [...context.params];
  const dedupeKey = listingDedupeSql('l');
  const dedupeEnabled = !filters.listingId;

  const filteredSql = `
    SELECT
      l.id,
      l.source,
      l.country,
      l.source_id,
      l.created_at,
      l.first_seen_at,
      l.price,
      l.currency,
      l.title,
      l.deal_type,
      l.by_agency,
      l.city,
      l.district,
      l.metro,
      l.data,
      ${context.priceUsdExpr} AS price_usd,
      ${context.rankSelect},
      ${dedupeEnabled ? dedupeKey : `CONCAT_WS(':', LOWER(l.source), UPPER(l.country), l.source_id)`} AS dedupe_key
    ${context.from}
    WHERE ${baseWhere}
  `;

  const rankedSql = `
    SELECT
      filtered.*,
      ROW_NUMBER() OVER (
        PARTITION BY filtered.dedupe_key
        ORDER BY filtered.created_at DESC NULLS LAST, filtered.id DESC
      ) AS dedupe_rank
    FROM (
      ${filteredSql}
    ) filtered
  `;

  const countSql = `
    SELECT COUNT(*)::int AS count
    FROM (
      ${rankedSql}
    ) l
    WHERE l.dedupe_rank = 1
  `;

  const statsSql = `
    WITH ranked AS MATERIALIZED (
      ${rankedSql}
    ),
    visible AS MATERIALIZED (
      SELECT * FROM ranked WHERE dedupe_rank = 1
    ),
    classified AS MATERIALIZED (
      SELECT
        visible.*,
        CASE
          WHEN data @> '{"roomOnly":true}'::jsonb THEN 'roomRent'
          WHEN deal_type IN ('sale', 'longRent', 'shortRent') THEN deal_type
          ELSE 'unknown'
        END AS deal_key
      FROM visible
    ),
    deal_rows AS (
      SELECT
        deal_key AS key,
        COUNT(*)::int AS count,
        COUNT(price_usd)::int AS price_count,
        ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_usd))::numeric, 2) AS median_usd,
        ROUND(AVG(price_usd)::numeric, 2) AS average_usd
      FROM classified
      GROUP BY deal_key
    ),
    geo_rows AS (
      SELECT
        CASE WHEN GROUPING(v.deal_key) = 1 THEN NULL ELSE v.deal_key END AS deal_key,
        geo.dimension,
        geo.label,
        COUNT(*)::int AS count,
        COUNT(v.price_usd)::int AS price_count,
        ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY v.price_usd))::numeric, 2) AS median_usd
      FROM classified v
      CROSS JOIN LATERAL (VALUES
        ('country', NULLIF(BTRIM(v.country), '')),
        ('city', NULLIF(BTRIM(v.city), '')),
        ('district', NULLIF(BTRIM(v.district), '')),
        ('microdistrict', NULLIF(BTRIM(v.data->>'microdistrict'), '')),
        ('metro', NULLIF(BTRIM(v.metro), ''))
      ) AS geo(dimension, label)
      WHERE geo.label IS NOT NULL
      GROUP BY GROUPING SETS (
        (geo.dimension, geo.label),
        (v.deal_key, geo.dimension, geo.label)
      )
    ),
    geo_ranked AS (
      SELECT *, ROW_NUMBER() OVER (PARTITION BY deal_key, dimension ORDER BY count DESC, label ASC) AS position
      FROM geo_rows
    ),
    geo_json AS (
      SELECT deal_key, dimension, JSONB_AGG(
        JSONB_BUILD_OBJECT(
          'label', label,
          'count', count,
          'priceCount', price_count,
          'medianUsd', median_usd
        ) ORDER BY count DESC, label ASC
      ) AS items
      FROM geo_ranked
      WHERE position <= 12
      GROUP BY deal_key, dimension
    ),
    geo_by_deal_json AS (
      SELECT deal_key, JSONB_OBJECT_AGG(dimension, items) AS dimensions
      FROM geo_json
      WHERE deal_key IS NOT NULL
      GROUP BY deal_key
    ),
    activity_rows AS (
      SELECT
        DATE_TRUNC('day', COALESCE(first_seen_at, created_at))::date AS day,
        COUNT(*)::int AS count
      FROM visible
      WHERE COALESCE(first_seen_at, created_at) IS NOT NULL
      GROUP BY 1
      ORDER BY 1
    )
    SELECT
      (SELECT COUNT(*)::int FROM visible) AS total,
      (SELECT COUNT(*)::int FROM ranked) AS raw_total,
      COALESCE((
        SELECT JSONB_AGG(JSONB_BUILD_OBJECT(
          'key', key,
          'count', count,
          'priceCount', price_count,
          'medianUsd', median_usd,
          'averageUsd', average_usd
        ) ORDER BY count DESC, key ASC)
        FROM deal_rows
      ), '[]'::jsonb) AS deal_types,
      COALESCE((SELECT JSONB_OBJECT_AGG(dimension, items) FROM geo_json WHERE deal_key IS NULL), '{}'::jsonb) AS geographies,
      COALESCE((SELECT JSONB_OBJECT_AGG(deal_key, dimensions) FROM geo_by_deal_json), '{}'::jsonb) AS geographies_by_deal,
      JSONB_BUILD_OBJECT(
        'owners', (SELECT COUNT(*)::int FROM visible WHERE by_agency = FALSE),
        'agencies', (SELECT COUNT(*)::int FROM visible WHERE by_agency = TRUE),
        'commission', (SELECT COUNT(*)::int FROM visible WHERE
          data @> '{"commission":true}'::jsonb
          OR (jsonb_typeof(data->'commissionPercent') = 'number' AND (data->>'commissionPercent')::numeric > 0)
        ),
        'noCommission', (SELECT COUNT(*)::int FROM visible WHERE
          data @> '{"commission":false}'::jsonb
          OR (jsonb_typeof(data->'commissionPercent') = 'number' AND (data->>'commissionPercent')::numeric = 0)
        )
      ) AS ownership,
      COALESCE((
        SELECT JSONB_AGG(JSONB_BUILD_OBJECT('date', day, 'count', count) ORDER BY day)
        FROM activity_rows
      ), '[]'::jsonb) AS activity,
      JSONB_BUILD_OBJECT(
        'duplicatesRejected', (SELECT COUNT(*)::int FROM ranked WHERE dedupe_rank > 1),
        'suspectedFake', (SELECT COUNT(*)::int FROM visible WHERE
          data->>'duplicatePhotoRisk' IN ('high', 'very_high')
          OR data->'antiFake' @> '{"suspectedClone":true}'::jsonb
          OR data->'antiFake' @> '{"conflictingClone":true}'::jsonb
        )
      ) AS quality
  `;

  const pageParams = [...baseParams];
  const addPage = (value) => {
    pageParams.push(value);
    return `$${pageParams.length}`;
  };

  const cursor = decodeCursor(filters.cursor);
  const pageWhere = ['l.dedupe_rank = 1'];
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
  const orderBy = context.orderBy.replaceAll('m.rank', 'l.search_rank');

  const pageSql = `
    SELECT
      l.id AS db_id,
      l.created_at,
      l.price,
      l.currency,
      l.title,
      l.data,
      l.search_rank
    FROM (
      ${rankedSql}
    ) l
    WHERE ${pageWhere.join('\n      AND ')}
    ORDER BY ${orderBy}
    LIMIT ${limitParam}
    OFFSET ${offsetParam}
  `;

  let countOrStatsResult;
  let pageResult = {rows: []};
  if (filters.includeStats && filters.statsOnly) {
    countOrStatsResult = await pool.query(statsSql, baseParams);
  } else {
    [countOrStatsResult, pageResult] = await Promise.all([
      filters.includeStats ? pool.query(statsSql, baseParams) : pool.query(countSql, baseParams),
      pool.query(pageSql, pageParams),
    ]);
  }

  const rows = pageResult.rows;
  const listings = rows.map((row) => row.data || {});
  const statistics = filters.includeStats ? {
    total: Number(countOrStatsResult.rows[0]?.total) || 0,
    rawTotal: Number(countOrStatsResult.rows[0]?.raw_total) || 0,
    currency: 'USD',
    dealTypes: countOrStatsResult.rows[0]?.deal_types || [],
    geographies: countOrStatsResult.rows[0]?.geographies || {},
    geographiesByDeal: countOrStatsResult.rows[0]?.geographies_by_deal || {},
    ownership: countOrStatsResult.rows[0]?.ownership || {},
    activity: countOrStatsResult.rows[0]?.activity || [],
    quality: countOrStatsResult.rows[0]?.quality || {},
  } : null;
  const count = statistics?.total ?? (Number(countOrStatsResult.rows[0]?.count) || 0);

  let nextCursor = null;
  if (!filters.statsOnly && rows.length === limit && ['newest', 'oldest'].includes(context.sort)) {
    const last = rows[rows.length - 1];
    const time = last.created_at instanceof Date
      ? last.created_at.toISOString()
      : (last.created_at ? new Date(last.created_at).toISOString() : null);
    nextCursor = encodeCursor({ v: CURSOR_VERSION, sort: context.sort, t: time, id: String(last.db_id) });
  }

  return {
    count,
    listings,
    ...(statistics ? {statistics} : {}),
    nextCursor,
    queryMs: Math.round((performance.now() - startedAt) * 10) / 10,
    searchPath: searchMatches ? 'postgres+elasticsearch' : 'postgres',
  };
}
