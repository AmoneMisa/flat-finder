import {COUNTRIES, COUNTRY_CODES} from './countries.js';
import {getListings} from './scrapers/index.js';
import {applyListingFilters} from './legacy-listing-filter.js';
import {getRates} from './fx.js';
import {sortListings} from './listing-sort.js';
import {refreshAll} from './scheduler.js';
import {searchPostgresListings} from './postgres-search.js';
import {searchListingMatches} from './elasticsearch.js';
import {checkRate} from './request-rate-limit.js';

const VALID_SOURCES = ['olx', 'telegram'];
const VALID_SORTS = [
  'newest',
  'oldest',
  'priceAsc',
  'priceDesc',
  'titleAsc',
  'titleDesc',
];

export function parseListingFilters(q) {
  const num = (v) => (v == null || v === '' ? null : Number(v));
  const bool = (v) => (v === 'true' || v === '1' ? true : null);
  const sources = String(q.sources || '')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter((s) => VALID_SOURCES.includes(s));
  const customSources = [
    ...new Set(
      String(q.customSources || '')
        .split(',')
        .map((s) => s.trim())
        .filter((s) => /^https?:\/\//i.test(s)),
    ),
  ].slice(0, 10);

  return {
    customSources,
    propertyType: ['flat', 'house', 'any'].includes(q.propertyType) ? q.propertyType : 'any',
    dealType: ['sale', 'longRent', 'shortRent', 'any'].includes(q.dealType) ? q.dealType : 'any',
    agency: ['owner', 'agency', 'any'].includes(q.agency) ? q.agency : 'any',
    audience: ['women', 'men', 'family', 'any'].includes(q.audience) ? q.audience : 'any',
    priceMin: num(q.priceMin),
    priceMax: num(q.priceMax),
    priceTolerance: num(q.priceTolerance),
    priceCurrency: q.priceCurrency ? String(q.priceCurrency).toUpperCase() : null,
    roomsMin: num(q.roomsMin),
    roomsMax: num(q.roomsMax),
    bedroomsMin: num(q.bedroomsMin),
    bedroomsMax: num(q.bedroomsMax),
    areaMin: num(q.areaMin),
    areaMax: num(q.areaMax),
    metroMaxM: num(q.metroMaxM),
    nearbyMaxM: num(q.nearbyMaxM),
    nearbyKind: q.nearbyKind ? String(q.nearbyKind).toLowerCase() : null,
    pricePerSqmMin: num(q.pricePerSqmMin),
    pricePerSqmMax: num(q.pricePerSqmMax),
    floorMin: num(q.floorMin),
    floorMax: num(q.floorMax),
    totalFloorsMin: num(q.totalFloorsMin),
    totalFloorsMax: num(q.totalFloorsMax),
    yearMin: num(q.yearMin),
    yearMax: num(q.yearMax),
    newBuilding: bool(q.newBuilding),
    dishwasher: bool(q.dishwasher),
    airConditioner: bool(q.airConditioner),
    parking: bool(q.parking),
    internet: bool(q.internet),
    gas: bool(q.gas),
    balcony: bool(q.balcony),
    terrace: bool(q.terrace),
    privateYard: bool(q.privateYard),
    sort: VALID_SORTS.includes(q.sort) ? q.sort : null,
    city: q.city ? String(q.city) : '',
    district: q.district ? String(q.district) : '',
    metro: q.metro ? String(q.metro) : '',
    query: q.query ? String(q.query) : '',
    listingId: q.listingId ? String(q.listingId) : '',
    pets: bool(q.pets),
    children: bool(q.children),
    roomOnly: bool(q.roomOnly),
    maxAgeDays: num(q.maxAgeDays),
    sources,
    offset: num(q.offset) ?? 0,
    limit: Math.min(num(q.limit) ?? 40, 60),
    cursor: q.cursor ? String(q.cursor) : '',
  };
}

function listingSearchKey(listing) {
  return [
    String(listing.source || '').toLowerCase(),
    String(listing.country || '').toUpperCase(),
    String(listing.id),
  ].join(':');
}

function compareListingsByDate(a, b) {
  const ta = a.createdAt ? Date.parse(a.createdAt) : NaN;
  const tb = b.createdAt ? Date.parse(b.createdAt) : NaN;
  const va = Number.isNaN(ta) ? -Infinity : ta;
  const vb = Number.isNaN(tb) ? -Infinity : tb;
  return vb - va;
}

function resolveCountries(query) {
  const requested = String(query.countries || COUNTRY_CODES.join(','))
    .split(',')
    .map((value) => value.trim().toUpperCase())
    .filter((country) => COUNTRY_CODES.includes(country));

  return requested.length ? requested : COUNTRY_CODES;
}

function addCityAliases(filters, codes) {
  if (!filters.city) return;

  const forms = new Set([filters.city]);
  for (const code of codes) {
    for (const alias of COUNTRIES[code]?.cityAliases?.[filters.city] ?? []) {
      forms.add(alias);
    }
  }
  filters.cityAliases = [...forms];
}

async function tryPostgresSearch({filters, codes, force}) {
  if (force) {
    void refreshAll('manual').catch((err) => {
      console.warn('[postgres-search] background refresh failed:', err?.message ?? err);
    });
  }

  let searchError = null;
  const searchMatches = filters.query
    ? await searchListingMatches(filters.query, {
        countries: codes,
        sources: filters.sources,
      }).catch((err) => {
        searchError = err?.message ?? String(err);
        console.warn(`[elasticsearch] postgres search fallback: ${searchError}`);
        return null;
      })
    : null;

  let fxRates = null;
  try {
    fxRates = (await getRates()).rates;
  } catch {}

  const result = await searchPostgresListings({
    filters,
    countries: codes,
    rates: fxRates,
    searchMatches,
  });

  return {
    count: result.count,
    degradedCountries: [],
    sourceCounts: {},
    sourceErrors: searchError
      ? [{source: 'elasticsearch', error: searchError}]
      : [],
    warming: false,
    filters,
    searchEngine: filters.query
      ? (searchMatches ? 'elasticsearch+postgres' : 'postgres-fallback')
      : 'postgres',
    searchIndexedMatches: searchMatches?.total ?? null,
    searchTruncated: searchMatches?.truncated ?? false,
    queryMs: result.queryMs,
    nextCursor: result.nextCursor,
    listings: result.listings,
  };
}

async function legacySnapshotSearch({filters, codes, force}) {
  let searchError = null;
  const searchPromise = filters.query
    ? searchListingMatches(filters.query, {
        countries: codes,
        sources: filters.sources,
      }).catch((err) => {
        searchError = err?.message ?? String(err);
        console.warn(`[elasticsearch] search fallback: ${searchError}`);
        return null;
      })
    : Promise.resolve(null);

  const [results, searchMatches] = await Promise.all([
    Promise.all(
      codes.map((code) => getListings(code, filters, {force})),
    ),
    searchPromise,
  ]);

  const degraded = [];
  const sourceCounts = {};
  const sourceErrors = [];
  let warming = false;
  let listings = [];

  results.forEach((result, index) => {
    if (result.degraded) degraded.push(codes[index]);
    if (result.warming) warming = true;

    for (const [name, count] of Object.entries(result.sourceCounts ?? {})) {
      sourceCounts[name] = (sourceCounts[name] ?? 0) + count;
    }

    if (Array.isArray(result.sourceErrors)) {
      sourceErrors.push(...result.sourceErrors);
    }

    listings = listings.concat(result.listings);
  });

  let fxRates = null;
  try {
    fxRates = (await getRates()).rates;
  } catch {}

  const memoryFilters = searchMatches
    ? {...filters, query: ''}
    : filters;

  listings = applyListingFilters(listings, memoryFilters, fxRates);

  if (searchMatches) {
    listings = listings.filter((listing) =>
      searchMatches.rank.has(listingSearchKey(listing)),
    );

    listings.sort((a, b) => {
      const rankA = searchMatches.rank.get(listingSearchKey(a));
      const rankB = searchMatches.rank.get(listingSearchKey(b));
      if (rankA !== rankB) return rankA - rankB;
      return compareListingsByDate(a, b);
    });
  } else {
    listings.sort(compareListingsByDate);
  }

  if (filters.sort) {
    sortListings(listings, filters.sort, fxRates);
  }

  const count = listings.length;
  const offset = Math.max(0, filters.offset || 0);
  const page = listings.slice(offset, offset + filters.limit);

  return {
    count,
    degradedCountries: degraded,
    sourceCounts,
    sourceErrors,
    warming,
    filters,
    searchEngine: filters.query
      ? (searchMatches ? 'elasticsearch' : 'fallback')
      : null,
    searchIndexedMatches: searchMatches?.total ?? null,
    searchTruncated: searchMatches?.truncated ?? false,
    listings: page,
  };
}

export function installListingRoutes(app) {
  app.get('/api/listings', async (req, res) => {
    const force = req.query.refresh === '1' || req.query.refresh === 'true';

    if (force && !checkRate(req, res, 'reloadAll', 8000)) {
      return;
    }

    const filters = parseListingFilters(req.query);
    const codes = resolveCountries(req.query);
    addCityAliases(filters, codes);

    if (!filters.customSources.length) {
      try {
        const response = await tryPostgresSearch({filters, codes, force});
        return res.json(response);
      } catch (err) {
        console.warn(
          '[postgres-search] fast path failed, using legacy fallback:',
          err?.message ?? err,
        );
      }
    }

    try {
      const response = await legacySnapshotSearch({filters, codes, force});
      return res.json(response);
    } catch (err) {
      return res.status(500).json({
        error: err?.message ?? String(err),
      });
    }
  });
}
