import express from 'express';
import cors from 'cors';
import { COUNTRIES, COUNTRY_CODES } from './countries.js';
import { cityLocations } from './locations.js';
import { getListings } from './scrapers/index.js';
import { applyFilters } from './normalize.js';
import { getRates } from './fx.js';
import { startScheduler, refreshAll, getLastRun } from './scheduler.js';

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 4000;

// Metadata for the app: which countries/currencies/map centers exist.
app.get('/api/countries', (_req, res) => {
  res.json(
    COUNTRY_CODES.map((code) => {
      const c = COUNTRIES[code];
      return {
        code: c.code,
        name: c.name,
        currency: c.currency,
        center: c.center,
        cities: c.cities ?? [],
        locations: cityLocations(c.code), // { city: { districts, metro } }
      };
    }),
  );
});

const VALID_SOURCES = ['olx', 'reddit', 'telegram', 'threads'];

function parseFilters(q) {
  const num = (v) => (v == null || v === '' ? null : Number(v));
  const sources = String(q.sources || '')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter((s) => VALID_SOURCES.includes(s));
  return {
    propertyType: ['flat', 'house', 'any'].includes(q.propertyType) ? q.propertyType : 'any',
    dealType: ['sale', 'longRent', 'shortRent', 'any'].includes(q.dealType) ? q.dealType : 'any',
    agency: ['owner', 'agency', 'any'].includes(q.agency) ? q.agency : 'any',
    audience: ['women', 'men', 'family', 'any'].includes(q.audience) ? q.audience : 'any',
    priceMin: num(q.priceMin),
    priceMax: num(q.priceMax),
    roomsMin: num(q.roomsMin),
    roomsMax: num(q.roomsMax),
    bedroomsMin: num(q.bedroomsMin),
    bedroomsMax: num(q.bedroomsMax),
    floorMin: num(q.floorMin),
    floorMax: num(q.floorMax),
    yearMin: num(q.yearMin),
    yearMax: num(q.yearMax),
    city: q.city ? String(q.city) : '',
    district: q.district ? String(q.district) : '',
    metro: q.metro ? String(q.metro) : '',
    query: q.query ? String(q.query) : '',
    sources, // empty array = all sources
    offset: num(q.offset) ?? 0,
    limit: Math.min(num(q.limit) ?? 40, 60),
  };
}

// Main search endpoint. Accepts a comma-separated list of country codes.
// GET /api/listings?countries=RO,UA&propertyType=flat&agency=owner&priceMin=&priceMax=&query=
app.get('/api/listings', async (req, res) => {
  const filters = parseFilters(req.query);
  const requested = String(req.query.countries || COUNTRY_CODES.join(','))
    .split(',')
    .map((s) => s.trim().toUpperCase())
    .filter((c) => COUNTRY_CODES.includes(c));

  const codes = requested.length ? requested : COUNTRY_CODES;

  // Resolve the selected city to its localized forms (OLX/posts use Cyrillic or
  // diacritics, the dropdown sends the English name), so the city filter matches.
  if (filters.city) {
    const forms = new Set([filters.city]);
    for (const code of codes) {
      for (const alias of COUNTRIES[code]?.cityAliases?.[filters.city] ?? []) forms.add(alias);
    }
    filters.cityAliases = [...forms];
  }

  try {
    const results = await Promise.all(codes.map((code) => getListings(code, filters)));
    const degraded = [];
    const sourceCounts = {};
    let listings = [];
    results.forEach((r, i) => {
      if (r.degraded) degraded.push(codes[i]);
      for (const [name, n] of Object.entries(r.sourceCounts ?? {})) {
        sourceCounts[name] = (sourceCounts[name] ?? 0) + n;
      }
      listings = listings.concat(r.listings);
    });

    // Enforce filters the source could not (e.g. mock fallback, agency guess).
    listings = applyFilters(listings, filters);

    res.json({
      count: listings.length,
      degradedCountries: degraded, // countries currently served from demo data
      sourceCounts, // live listings fetched per source before filtering
      filters,
      listings,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Exchange rates (relative to USD) for client-side price normalization.
app.get('/api/rates', async (_req, res) => {
  try {
    const { base, rates, at } = await getRates();
    res.json({ base, rates, fetchedAt: new Date(at).toISOString() });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/health', (_req, res) => res.json({ ok: true }));

// Status of the background refresher (last run stats).
app.get('/api/refresh', (_req, res) => res.json({ lastRun: getLastRun() }));

// Trigger an immediate refresh of all countries (handy for testing / on-demand).
app.post('/api/refresh', async (_req, res) => {
  const result = await refreshAll('manual');
  res.json({ ok: true, result });
});

app.listen(PORT, () => {
  console.log(`flat-finder backend listening on http://localhost:${PORT}`);
  console.log(`countries: ${COUNTRY_CODES.join(', ')}`);
  startScheduler();
});
