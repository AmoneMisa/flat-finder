// Source registry + in-memory TTL cache.
//
// Each country runs several sources in parallel (see COUNTRIES[code].sources).
// Results are merged and de-duplicated. If every source for a country yields
// nothing (all blocked/empty), we fall back to generated demo data so the
// client never sees an empty screen for that country.

import { COUNTRIES } from '../countries.js';
import { scrapeOlx } from './olx.js';
import { scrapeReddit } from './reddit.js';
import { scrapeTelegram } from './telegram.js';
import { scrapeThreads } from './threads.js';
import { scrapeCustom } from './custom.js';
import { generateMock } from '../mock.js';
import { cacheGet, cacheSet } from '../cache.js';

const SOURCES = {
  olx: scrapeOlx,
  reddit: scrapeReddit,
  telegram: scrapeTelegram,
  threads: scrapeThreads,
};

// How long a cached entry is considered "fresh" (served without a re-scrape).
const CACHE_TTL_MS = 5 * 60 * 1000;
// How long a stale entry is still kept and served (while a refresh runs in the
// background). This is the Redis retention window for each key.
const STALE_TTL_MS = 60 * 60 * 1000;
// De-dupe concurrent background refreshes of the same key.
const inFlight = new Map(); // key -> Promise

// Hard backstop so a single misbehaving source can never stall the whole
// country response past the proxy timeout. Sources have their own (tighter)
// internal budgets; this only fires in pathological cases and yields whatever
// the source returned before the deadline (empty on timeout).
const SOURCE_DEADLINE_MS = Number(process.env.SOURCE_DEADLINE_MS) || 15000;

function withDeadline(promise, ms, onTimeout) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => resolve(onTimeout), ms);
    promise.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      },
    );
  });
}

function cacheKey(countryCode, filters) {
  return [
    countryCode,
    filters.propertyType ?? 'any',
    filters.dealType ?? 'any',
    filters.agency ?? 'any',
    filters.priceMin ?? '',
    filters.priceMax ?? '',
    filters.query ?? '',
    (filters.sources ?? []).join('+') || 'all',
    (filters.customSources ?? []).join('+') || '',
    filters.offset ?? 0,
  ].join('|');
}

function dedupe(listings) {
  const seen = new Set();
  const out = [];
  for (const l of listings) {
    const key = `${l.source}:${l.id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(l);
  }
  return out;
}

async function fetchOne(countryCode, filters) {
  const country = COUNTRIES[countryCode];
  if (!country) return { listings: [], degraded: false, sourceCounts: {}, sourceErrors: [] };

  let sources = country.sources ?? ['olx'];
  // Restrict to the sources the user selected (empty selection = all).
  if (filters.sources && filters.sources.length) {
    sources = sources.filter((s) => filters.sources.includes(s));
  }
  const results = await Promise.allSettled(
    sources.map(async (name) => {
      const fn = SOURCES[name];
      if (!fn) return { name, listings: [] };
      const listings = await withDeadline(fn(country, filters), SOURCE_DEADLINE_MS, []);
      return { name, listings };
    }),
  );

  const sourceCounts = {};
  const sourceErrors = [];
  let merged = [];
  results.forEach((r, i) => {
    const name = sources[i];
    if (r.status === 'fulfilled') {
      sourceCounts[name] = r.value.listings.length;
      merged = merged.concat(r.value.listings);
    } else {
      sourceCounts[name] = 0;
      const msg = r.reason?.message ?? String(r.reason);
      sourceErrors.push({ source: name, country: countryCode, error: msg });
      console.warn(`[scraper] ${countryCode}/${name} failed: ${msg}`);
    }
  });

  // User-provided custom sources: fetched per URL, failures surfaced individually.
  if (Array.isArray(filters.customSources) && filters.customSources.length) {
    const custom = await scrapeCustom(country, filters);
    sourceCounts.custom = custom.listings.length;
    merged = merged.concat(custom.listings);
    for (const e of custom.errors) {
      sourceErrors.push({ source: 'custom', country: countryCode, url: e.url, error: e.error });
    }
  }

  merged = dedupe(merged);

  if (!merged.length) {
    console.warn(`[scraper] ${countryCode} all sources empty -> mock`);
    return { listings: generateMock(countryCode), degraded: true, sourceCounts, sourceErrors };
  }
  return { listings: merged, degraded: false, sourceCounts, sourceErrors };
}

// Scrape a country fresh and store the result in the (Redis or in-memory) cache.
// Concurrent callers for the same key share a single in-flight scrape.
function refresh(countryCode, filters, key) {
  if (inFlight.has(key)) return inFlight.get(key);
  const p = (async () => {
    const result = await fetchOne(countryCode, filters);
    const entry = { at: Date.now(), ...result };
    await cacheSet(key, entry, STALE_TTL_MS);
    return entry;
  })().finally(() => inFlight.delete(key));
  inFlight.set(key, p);
  return p;
}

// Stale-while-revalidate:
//   fresh cache hit  -> return immediately
//   stale cache hit  -> return the stale copy now, refresh in the background
//   miss             -> scrape synchronously
// This means a user request never blocks on a slow telegram scrape once the
// key has been warmed at least once, which is what caused the 504s / few results.
export async function getListings(countryCode, filters, { force = false } = {}) {
  const key = cacheKey(countryCode, filters);
  if (force) return refresh(countryCode, filters, key);

  const hit = await cacheGet(key);
  if (hit) {
    const age = Date.now() - hit.at;
    if (age < CACHE_TTL_MS) return hit; // fresh
    // Stale: kick off a background refresh but serve the cached copy now.
    refresh(countryCode, filters, key).catch((e) =>
      console.warn(`[scraper] background refresh ${countryCode} failed: ${e.message}`),
    );
    return hit;
  }
  return refresh(countryCode, filters, key);
}

// Default "browse" filters — the query the app sends when no filters are set.
// The hourly warmer refreshes this key so the common view is always instant.
export const BASE_FILTERS = {
  propertyType: 'any',
  dealType: 'any',
  agency: 'any',
  priceMin: null,
  priceMax: null,
  query: '',
  sources: [],
  offset: 0,
  limit: 50,
};

// Force-refresh the default browse cache for one country (bypasses the TTL).
export async function warmCountry(countryCode) {
  return getListings(countryCode, BASE_FILTERS, { force: true });
}
