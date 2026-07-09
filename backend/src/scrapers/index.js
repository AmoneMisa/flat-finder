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
import { generateMock } from '../mock.js';

const SOURCES = {
  olx: scrapeOlx,
  reddit: scrapeReddit,
  telegram: scrapeTelegram,
  threads: scrapeThreads,
};

const CACHE_TTL_MS = 5 * 60 * 1000;
const cache = new Map(); // key -> { at, listings, degraded, sourceCounts }

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
  if (!country) return { listings: [], degraded: false, sourceCounts: {} };

  let sources = country.sources ?? ['olx'];
  // Restrict to the sources the user selected (empty selection = all).
  if (filters.sources && filters.sources.length) {
    sources = sources.filter((s) => filters.sources.includes(s));
  }
  const results = await Promise.allSettled(
    sources.map(async (name) => {
      const fn = SOURCES[name];
      if (!fn) return { name, listings: [] };
      const listings = await fn(country, filters);
      return { name, listings };
    }),
  );

  const sourceCounts = {};
  let merged = [];
  results.forEach((r, i) => {
    const name = sources[i];
    if (r.status === 'fulfilled') {
      sourceCounts[name] = r.value.listings.length;
      merged = merged.concat(r.value.listings);
    } else {
      sourceCounts[name] = 0;
      console.warn(`[scraper] ${countryCode}/${name} failed: ${r.reason?.message ?? r.reason}`);
    }
  });

  merged = dedupe(merged);

  if (!merged.length) {
    console.warn(`[scraper] ${countryCode} all sources empty -> mock`);
    return { listings: generateMock(countryCode), degraded: true, sourceCounts };
  }
  return { listings: merged, degraded: false, sourceCounts };
}

export async function getListings(countryCode, filters, { force = false } = {}) {
  const key = cacheKey(countryCode, filters);
  const hit = cache.get(key);
  if (!force && hit && Date.now() - hit.at < CACHE_TTL_MS) return hit;

  const result = await fetchOne(countryCode, filters);
  const entry = { at: Date.now(), ...result };
  cache.set(key, entry);
  return entry;
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
