// Source registry + in-memory TTL cache.
//
// Each country runs several sources in parallel (see COUNTRIES[code].sources).
// Results are merged and de-duplicated. If every source for a country yields
// nothing (all blocked/empty), we fall back to generated demo data so the
// client never sees an empty screen for that country.

import { createHash } from 'node:crypto';
import { COUNTRIES } from '../countries.js';
import { scrapeOlx } from './olx.js';
import { scrapeTelegram } from './telegram.js';
import { scrapeCustom } from './custom.js';
import { generateMock } from '../mock.js';
import { cacheGet, cacheSet } from '../cache.js';
import { geocodeListings } from '../geocode.js';
import {
  aiFingerprint,
  aiWorkerEnabled,
  scheduleAiExtraction,
} from '../ai-worker.js';

const SOURCES = {
  olx: scrapeOlx,
  telegram: scrapeTelegram,
};

// How long a cached entry is considered "fresh" (served without a re-scrape).
const CACHE_TTL_MS = 5 * 60 * 1000;
// How long a stale entry is still kept and served (while a refresh runs in the
// background). This is the Redis retention window for each key.
const STALE_TTL_MS = 60 * 60 * 1000;
// While a scrape is in progress, partial snapshots are written to the cache no
// more often than this so the UI count/results climb as chunks arrive without
// hammering Redis. The final complete snapshot is always written.
const PARTIAL_WRITE_MS = Number(process.env.PARTIAL_WRITE_MS) || 1200;
// De-dupe concurrent background refreshes of the same key.
const inFlight = new Map(); // key -> Promise

// Hard backstop so a single misbehaving source can never stall the whole
// country response past the proxy timeout. Sources have their own (tighter)
// internal budgets; this only fires in pathological cases and yields whatever
// the source returned before the deadline (empty on timeout).
// Must sit above telegram's own budget (TG_BUDGET_MS ~12s) plus one in-flight
// page fetch (~8s), so telegram returns its partial set on the budget rather
// than being killed here and discarded entirely (which showed as demo data).
const SOURCE_DEADLINE_MS = Number(process.env.SOURCE_DEADLINE_MS) || 24000;

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
    // Bump this when the snapshot shape/semantics change so Redis cannot serve
    // an older cache whose rows were already narrowed by a UI filter.
    'full-feed-v4',
    countryCode,
    // UI filters are deliberately absent. Like the vacancy store, this cache
    // is one complete country snapshot; /api/listings filters and paginates it
    // in memory. Changing a select must never launch a new scrape or mutate the
    // meaning of rows stored under a different filter combination.
    'all-sources',
    (filters.customSources ?? []).join('+') || '',
  ].join('|');
}

// Scrapers populate the shared snapshot and therefore must never receive the
// user's current search filters. Those filters are applied only after the
// cached snapshots have been merged in server.js. Keeping custom source URLs is
// intentional: they define the contents of a snapshot rather than a view of it.
function snapshotFilters(filters) {
  return {
    ...filters,
    propertyType: 'any',
    dealType: 'any',
    agency: 'any',
    priceMin: null,
    priceMax: null,
    priceTolerance: null,
    roomsMin: null,
    roomsMax: null,
    bedroomsMin: null,
    bedroomsMax: null,
    floorMin: null,
    floorMax: null,
    yearMin: null,
    yearMax: null,
    audience: 'any',
    city: '',
    cityAliases: [],
    district: '',
    metro: '',
    query: '',
    pets: null,
    children: null,
    roomOnly: null,
    maxAgeDays: null,
    sources: [],
    offset: 0,
    limit: 50,
  };
}

// Content fingerprint: identical reposts (same text/photo across channels or a
// channel reposting itself) get different message ids, so id-dedup alone misses
// them. Hash the normalized title+description; for near-empty text fall back to
// the structured key so we don't collapse distinct short posts (spec §27).
function contentFingerprint(l) {
  const text = `${l.title || ''} ${l.description || ''}`
    .toLowerCase()
    .replace(/https?:\/\/\S+/g, '')
    .replace(/[^a-zа-яёіїґ0-9]+/g, '')
    .slice(0, 600);
  if (text.length >= 40) return `t:${createHash('sha1').update(text).digest('hex')}`;
  return `k:${[l.price, l.currency, l.rooms, l.areaSqm, l.district, l.city].join('|').toLowerCase()}`;
}

function dedupe(listings) {
  const seenId = new Set();
  const seenContent = new Set();
  const out = [];
  for (const l of listings) {
    const id = `${l.source}:${l.id}`;
    if (seenId.has(id)) continue;
    const fp = contentFingerprint(l);
    if (seenContent.has(fp)) continue; // identical repost — keep the first
    seenId.add(id);
    seenContent.add(fp);
    out.push(l);
  }
  return out;
}

function listingKey(listing) {
  return `${listing.source}:${listing.id}`;
}

function apartmentAiInput(listing) {
  const rawText = `${listing.title || ''}\n${listing.description || ''}`.trim();
  const dealMap = { longRent: 'rent', shortRent: 'daily_rent', sale: 'sale' };
  const knownFacts = {
    dealType: dealMap[listing.dealType] ?? null,
    propertyType: listing.propertyType === 'house' ? 'house' : 'apartment',
    rooms: listing.rooms ?? null,
    bedrooms: listing.bedrooms ?? null,
    areaM2: listing.areaSqm ?? null,
    floor: listing.floor ?? null,
    floorsTotal: listing.totalFloors ?? null,
    district: listing.district ?? null,
    kvartal: listing.kvartal ?? null,
    newBuilding: listing.newBuilding ?? null,
    balcony: listing.balcony ?? null,
    airConditioner: listing.airConditioner ?? null,
    gas: listing.gas ?? null,
    bathrooms: listing.bathrooms ?? null,
    furnished: listing.furnished ?? null,
    petsAllowed: listing.petsAllowed ?? null,
    childrenAllowed: listing.childrenAllowed ?? null,
    communalSeparated: listing.communalSeparated ?? null,
    depositRequired: listing.deposit ?? null,
    depositAmount: listing.depositAmount ?? null,
    commissionRequired: listing.commission ?? null,
    commissionPercent: listing.commissionPercent ?? null,
    priceAmount: listing.price ?? null,
    priceCurrency: listing.currency ?? null,
    negotiable: listing.negotiable ?? null,
    parking: listing.parking ?? null,
    elevator: listing.elevator ?? null,
    heating: listing.heating ?? null,
    hotWater: listing.hotWater ?? null,
    internet: listing.internet ?? null,
    smokingAllowed: listing.smokingAllowed ?? null,
  };
  return {
    rawText,
    knownFacts,
    fingerprint: aiFingerprint('apartment', rawText, knownFacts),
  };
}

function mergeApartmentAi(listing, data) {
  const merged = { ...listing };
  const fill = (field, value) => {
    if ((merged[field] == null || merged[field] === '') && value != null) merged[field] = value;
  };
  fill('rooms', data.rooms);
  fill('bedrooms', data.bedrooms);
  fill('areaSqm', data.areaM2);
  fill('floor', data.floor);
  fill('totalFloors', data.floorsTotal);
  fill('district', data.district);
  fill('kvartal', data.kvartal);
  fill('newBuilding', data.newBuilding);
  fill('balcony', data.balcony);
  fill('airConditioner', data.airConditioner);
  fill('gas', data.gas);
  fill('bathrooms', data.bathrooms);
  fill('furnished', data.furnished);
  fill('petsAllowed', data.petsAllowed);
  fill('childrenAllowed', data.childrenAllowed);
  fill('communalSeparated', data.communalSeparated);
  fill('deposit', data.depositRequired);
  fill('depositAmount', data.depositAmount);
  fill('commission', data.commissionRequired);
  fill('commissionPercent', data.commissionPercent);
  fill('negotiable', data.negotiable);
  fill('parking', data.parking);
  fill('elevator', data.elevator);
  fill('heating', data.heating);
  fill('hotWater', data.hotWater);
  fill('internet', data.internet);
  fill('smokingAllowed', data.smokingAllowed);
  fill('utilitiesAmount', data.utilitiesAmount);
  fill('minLeaseTerm', data.minLeaseTerm);
  fill('availableFrom', data.availableFrom);
  fill('price', data.priceAmount);
  if (!merged.currency && data.priceCurrency) merged.currency = data.priceCurrency;
  fill('condition', data.condition);

  if (!merged.dealType && data.dealType) {
    merged.dealType = { rent: 'longRent', daily_rent: 'shortRent', sale: 'sale' }[data.dealType] ?? null;
  }
  if (data.propertyType === 'house' && !merged.propertyType) merged.propertyType = 'house';
  if (data.propertyType === 'room') merged.roomOnly = true;
  if (data.propertyType === 'commercial') merged.commercial = true;
  merged.amenities = [...new Set([...(merged.amenities || []), ...(data.amenities || [])])];
  return merged;
}

function apartmentNeedsAi(listing) {
  if ((listing.description || '').length < 80 || String(listing.source).startsWith('mock')) return false;
  let score = 0;
  if (listing.rooms == null) score += 2;
  if (listing.areaSqm == null) score += 2;
  if (listing.floor == null || listing.totalFloors == null) score += 1;
  if (!listing.district) score += 1;
  if (listing.deposit == null && listing.commission == null) score += 1;
  if (listing.balcony == null && listing.airConditioner == null && listing.gas == null) score += 1;
  return score >= 3;
}

async function applyApartmentAiResult(cacheKeyValue, id, fingerprint, result) {
  const entry = await cacheGet(cacheKeyValue);
  if (!entry?.complete) return;
  const index = entry.listings.findIndex((listing) => listingKey(listing) === id);
  if (index < 0) return;
  const current = entry.listings[index];
  if (apartmentAiInput(current).fingerprint !== fingerprint) return;
  const accepted = !result.lowConfidence && result.confidence >= 0.6;
  if (accepted) entry.listings[index] = mergeApartmentAi(current, result.data);
  entry.ai = entry.ai || {};
  entry.ai[id] = {
    fingerprint,
    status: accepted ? 'completed' : 'low_confidence',
    confidence: result.confidence,
    data: accepted ? result.data : undefined,
    updatedAt: new Date().toISOString(),
  };
  await cacheSet(cacheKeyValue, entry, STALE_TTL_MS);
}

function scheduleApartmentAi(cacheKeyValue, entry) {
  if (!aiWorkerEnabled()) return 0;
  // Per country refresh. Five keeps the initial five-country rollout bounded;
  // terminal records are skipped so later refreshes naturally advance.
  const batchSize = Math.max(1, Number(process.env.AI_WORKER_APARTMENT_BATCH) || 5);
  entry.ai = entry.ai || {};
  let count = 0;
  for (const listing of entry.listings) {
    if (count >= batchSize) break;
    if (!apartmentNeedsAi(listing)) continue;
    const id = listingKey(listing);
    const input = apartmentAiInput(listing);
    const prior = entry.ai[id];
    // `entry.ai` only contains metadata whose fingerprint matched the fresh
    // deterministic listing above. Completed results may already have filled
    // fields and therefore intentionally change a newly computed fingerprint.
    if (prior && prior.status !== 'pending') continue;
    const queued = scheduleAiExtraction({
      id,
      kind: 'apartment',
      ...input,
      meta: { source: listing.source, country: listing.country, id: listing.id },
      onResult: (result) => applyApartmentAiResult(cacheKeyValue, id, input.fingerprint, result),
      onFailed: async (status) => {
        if (status !== 'failed') return;
        const current = await cacheGet(cacheKeyValue);
        if (!current?.complete) return;
        current.ai = current.ai || {};
        current.ai[id] = {
          fingerprint: input.fingerprint,
          status: 'failed',
          updatedAt: new Date().toISOString(),
        };
        await cacheSet(cacheKeyValue, current, STALE_TTL_MS);
      },
    });
    if (queued) {
      entry.ai[id] = { fingerprint: input.fingerprint, status: 'pending', updatedAt: new Date().toISOString() };
      count += 1;
    }
  }
  if (count) console.log(`[flats:ai] queued ${count} ambiguous listings for ${cacheKeyValue}`);
  return count;
}

// `onProgress({ listings, sourceCounts, sourceErrors })` (optional) is called as
// chunks/sources arrive so the caller can stream partial snapshots into the cache.
async function fetchOne(countryCode, filters, onProgress) {
  const country = COUNTRIES[countryCode];
  if (!country) return { listings: [], degraded: false, sourceCounts: {}, sourceErrors: [] };

  const sources = country.sources ?? ['olx'];
  const sourceCounts = {};
  const sourceErrors = [];
  let merged = [];
  const emit = () => {
    if (onProgress) onProgress({ listings: merged, sourceCounts: { ...sourceCounts }, sourceErrors: [...sourceErrors] });
  };

  const tasks = sources.map((name) => {
    const fn = SOURCES[name];
    if (!fn) { sourceCounts[name] = 0; return Promise.resolve(); }
    sourceCounts[name] = 0;
    // Sources that support it (OLX pages) stream partial results per chunk so the
    // count climbs during the scrape; others just resolve once at the end.
    const onChunk = (chunk) => {
      if (!chunk?.length) return;
      sourceCounts[name] += chunk.length;
      merged = dedupe(merged.concat(chunk));
      emit();
    };
    return withDeadline(fn(country, filters, onChunk), SOURCE_DEADLINE_MS, []).then(
      (listings) => {
        // Merge the source's authoritative result (no-op for chunks already
        // streamed; picks up non-streaming sources like Telegram). Reconcile the
        // per-source count to the source's own de-duplicated total.
        merged = dedupe(merged.concat(listings));
        sourceCounts[name] = Math.max(sourceCounts[name], listings.length);
        emit();
      },
      (err) => {
        const msg = err?.message ?? String(err);
        sourceErrors.push({ source: name, country: countryCode, error: msg });
        console.warn(`[scraper] ${countryCode}/${name} failed: ${msg}`);
        emit();
      },
    );
  });
  await Promise.allSettled(tasks);

  // User-provided custom sources: fetched per URL, failures surfaced individually.
  if (Array.isArray(filters.customSources) && filters.customSources.length) {
    const custom = await scrapeCustom(country, filters);
    sourceCounts.custom = custom.listings.length;
    merged = dedupe(merged.concat(custom.listings));
    for (const e of custom.errors) {
      sourceErrors.push({ source: 'custom', country: countryCode, url: e.url, error: e.error });
    }
    emit();
  }

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
    // Preserve AI provenance/results across deterministic source refreshes when
    // the source text and known facts are unchanged.
    const previousAi = (await cacheGet(key))?.ai || {};
    // Stream partial snapshots into the cache as chunks arrive so the client's
    // warm-poll sees the count/results climb. Partial writes are throttled and
    // serialized, and skip geocoding (that runs once on the final snapshot) to
    // keep them cheap. Marked complete:false so getListings keeps `warming` on.
    let lastWrite = 0;
    let writing = Promise.resolve();
    const onProgress = (partial) => {
      const now = Date.now();
      if (now - lastWrite < PARTIAL_WRITE_MS) return;
      lastWrite = now;
      writing = writing
        .then(() => cacheSet(key, { at: Date.now(), ...partial, degraded: false, complete: false }, STALE_TTL_MS))
        .catch(() => {});
    };

    const result = await fetchOne(countryCode, snapshotFilters(filters), onProgress);
    await writing; // ensure the final write below lands after any partial write
    // Place coordinate-less listings (Telegram/custom) on the map by geocoding
    // their address > metro > district > city. Throttled + cached; runs here in
    // the background refresh so it never delays a user request.
    try {
      await geocodeListings(result.listings, COUNTRIES[countryCode]);
    } catch (err) {
      console.warn(`[geocode] ${countryCode} failed: ${err.message}`);
    }
    const ai = {};
    result.listings = result.listings.map((listing) => {
      const id = listingKey(listing);
      const input = apartmentAiInput(listing);
      const prior = previousAi[id];
      if (prior?.fingerprint !== input.fingerprint) return listing;
      ai[id] = prior;
      return prior.status === 'completed' && prior.data
        ? mergeApartmentAi(listing, prior.data)
        : listing;
    });
    const entry = { at: Date.now(), ...result, ai, complete: true };
    await cacheSet(key, entry, STALE_TTL_MS);
    if (scheduleApartmentAi(key, entry)) await cacheSet(key, entry, STALE_TTL_MS);
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
    // An in-progress (partial) snapshot: serve what we have and keep the client
    // polling so the count/results climb as more chunks land. If no refresh is
    // actually running (e.g. the process restarted mid-scrape), resume one.
    if (hit.complete === false) {
      if (!inFlight.has(key)) {
        refresh(countryCode, filters, key).catch((e) =>
          console.warn(`[scraper] resume refresh ${countryCode} failed: ${e.message}`),
        );
      }
      return { ...hit, warming: true };
    }
    const age = Date.now() - hit.at;
    if (age < CACHE_TTL_MS) return { ...hit, warming: false }; // fresh
    // Stale: kick off a background refresh but serve the cached copy now.
    refresh(countryCode, filters, key).catch((e) =>
      console.warn(`[scraper] background refresh ${countryCode} failed: ${e.message}`),
    );
    return { ...hit, warming: true };
  }
  // Mirror the vacancy store: a cold request starts population in the
  // background and returns immediately. The web client polls while `warming`
  // is true, so nginx never waits for a 20+ second OLX/Telegram scrape.
  refresh(countryCode, filters, key).catch((e) =>
    console.warn(`[scraper] initial refresh ${countryCode} failed: ${e.message}`),
  );
  return {
    at: Date.now(),
    listings: [],
    degraded: false,
    sourceCounts: {},
    sourceErrors: [],
    warming: true,
  };
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
