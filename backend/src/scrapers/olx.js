// OLX adapter.
//
// OLX fronts its site with an AWS WAF that 403s plain HTTP clients from our
// server by TLS/JA3 fingerprint (both the private /api/v1 endpoint AND the HTML
// pages), while letting a real Chrome fingerprint through even from the same IP.
// So the country snapshot is fetched through the `olx-fetcher` sidecar
// (Python + curl_cffi, which impersonates Chrome). It returns the ad objects
// embedded in each real-estate page's `window.__PRERENDERED_STATE__`, which we
// map here. If OLX_FETCHER_URL is unset the source is disabled and yields
// nothing (the other sources still work).
//
// The /api/v1 path below is kept ONLY for the manual single-listing reload
// (fetchOlxOffer); it will 403 from a blocked server until it is also routed
// through the sidecar.

import { makeListing } from '../normalize.js';
import { guessPropertyType } from '../textparse.js';
import { throttle, sleep } from '../ratelimit.js';

// Pull several newest-first pages so enough recent listings survive the 3-week
// freshness filter. One page is ~50 ads; this ceiling (~500) bounds latency.
const OLX_MAX_PAGES = Number(process.env.OLX_MAX_PAGES) || 10;

// Rate limiting: keep at least OLX_MIN_INTERVAL_MS (+ up to OLX_JITTER_MS random)
// between requests to the same OLX portal so we don't hammer it. Keyed per host,
// so different countries throttle independently.
const OLX_MIN_INTERVAL_MS = Number(process.env.OLX_MIN_INTERVAL_MS) || 900;
const OLX_JITTER_MS = Number(process.env.OLX_JITTER_MS) || 500;
// On HTTP 429 (Too Many Requests), back off this long before the caller retries.
const OLX_BACKOFF_MS = Number(process.env.OLX_BACKOFF_MS) || 5_000;

const UA_HEADER =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

// Preferred UI language per portal, sent in Accept-Language so the response and
// the anti-bot check see a locale consistent with the host being requested.
const OLX_LANG = { RO: 'ro-RO,ro;q=0.9,en;q=0.7', UA: 'uk-UA,uk;q=0.9,ru;q=0.7,en;q=0.5', KZ: 'ru-RU,ru;q=0.9,kk;q=0.7,en;q=0.5', UZ: 'ru-RU,ru;q=0.9,uz;q=0.7,en;q=0.5' };

// OLX fronts its API with an anti-bot WAF that rejects requests missing the
// header set a real browser sends. A bare User-Agent gets an HTTP 403; sending
// the same-origin Referer/Origin, client hints and Sec-Fetch metadata that
// olx.<tld>'s own frontend sends clears the naive rules. (If the block is at the
// IP/TLS-fingerprint level this is not enough — an egress proxy is then needed.)
function browserHeaders(country) {
  const host = country.olxHost;
  return {
    'User-Agent': UA_HEADER,
    Accept: 'application/json, text/plain, */*',
    'Accept-Language': OLX_LANG[country.code] || 'en-US,en;q=0.9',
    Referer: `${host}/`,
    Origin: host,
    'sec-ch-ua': '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"',
    'Sec-Fetch-Dest': 'empty',
    'Sec-Fetch-Mode': 'cors',
    'Sec-Fetch-Site': 'same-origin',
  };
}

// URL of the olx-fetcher sidecar. Unset -> OLX source disabled (yields nothing).
const OLX_FETCHER_URL = process.env.OLX_FETCHER_URL || '';

// One rate-limited page fetch via the sidecar. Node throttles here (1:1 with the
// sidecar's outbound OLX request) so we stay a polite client to OLX.
async function fetchStatePage(country, page) {
  await throttle(`olx:${country.olxHost}`, OLX_MIN_INTERVAL_MS, OLX_JITTER_MS);
  const base = OLX_FETCHER_URL.replace(/\/$/, '');
  const url = `${base}/olx/listings?country=${country.code}&page=${page}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(30_000) });
  if (!res.ok) {
    let detail = `HTTP ${res.status}`;
    try { detail = (await res.json())?.error || detail; } catch { /* non-JSON body */ }
    throw new Error(`olx-fetcher ${country.code}: ${detail}`);
  }
  const data = await res.json();
  return Array.isArray(data?.ads) ? data.ads : [];
}

// Find a listing parameter by key or human name. Web-state params look like
// { key, name, type, value, normalizedValue }. Returns the display `value`.
function stateParam(item, keyRe, nameRe) {
  for (const p of item.params ?? []) {
    if ((p.key && keyRe.test(p.key)) || (p.name && nameRe.test(p.name))) return p.value;
  }
  return null;
}

function stateRooms(item) {
  const raw = stateParam(item, /room|komnat|kimnat|xonali|kolichestvo/i, /комнат|кімнат|room|xonali|спал/i);
  let rooms = raw != null ? Number(String(raw).match(/\d+/)?.[0]) : null;
  if (!rooms) {
    // Fall back to the title, but only on an explicit room word — never a bare
    // "кв" (that is "кв.м" area, e.g. "72 кв.м" is 72 m², not 72 rooms).
    const t = (item.title || '').match(
      /(\d+)\s*[-хx]?\s*(?:camer|комнатн|комн|кімнат|кімн|room|bedroom|xonali|xona)/i,
    );
    rooms = t ? Number(t[1]) : null;
  }
  if (rooms != null && (rooms < 1 || rooms > 10)) rooms = null; // sanity cap
  return rooms || null;
}

function stateArea(item) {
  const raw = stateParam(item, /area|m2|total_area|ploshch|maydon|kvadrat/i, /площад|area|m²|кв\.?\s*м|maydon|майдон/i);
  const n = raw != null ? Number(String(raw).replace(',', '.').match(/\d+(?:\.\d+)?/)?.[0]) : null;
  return n || null;
}

// Map one ad from a page's __PRERENDERED_STATE__ (a richer shape than /api/v1).
// The structured pieces we can get cheaply are passed to makeListing; the rest
// (dealType, floor, audience, tags, ...) is parsed from title/description there.
// Note: web-state ads carry real coordinates + city/district, so they need no
// geocoding downstream.
function mapStateItem(item, country) {
  const rp = item.price?.regularPrice ?? {};
  const paramText = (item.params ?? [])
    .map((p) => `${p.name ?? ''} ${Array.isArray(p.value) ? p.value.join(' ') : p.value ?? ''}`)
    .join(' ');
  return makeListing({
    id: item.id,
    source: 'olx',
    country: country.code,
    title: item.title,
    description: item.description ?? '',
    propertyType: guessPropertyType(`${item.title || ''} ${paramText}`),
    byAgency: Boolean(item.isBusiness),
    price: rp.value ?? null,
    currency: normalizeCurrency(rp.currencyCode) ?? country.currency,
    rooms: stateRooms(item),
    areaSqm: stateArea(item),
    city: item.location?.cityName ?? item.location?.regionName ?? '',
    district: item.location?.districtName ?? null,
    lat: item.map?.lat ?? null,
    lng: item.map?.lon ?? null,
    photos: Array.isArray(item.photos) ? item.photos.filter(Boolean) : [],
    url: item.url ?? country.olxHost,
    createdAt: item.createdTime ?? null,
  });
}

function paramMap(item) {
  const map = {};
  for (const pr of item.params ?? []) map[pr.key] = pr;
  return map;
}

function allPhotos(item) {
  return (item.photos ?? [])
    .map((p) => p.link?.replace('{width}', '800').replace('{height}', '600'))
    .filter(Boolean);
}

// OLX Uzbekistan quotes prices in "у.е." (conventional units) under the code
// "UYE" — a USD equivalent. Map it to USD so display-currency conversion works.
function normalizeCurrency(code) {
  if (!code) return null;
  const c = String(code).toUpperCase();
  if (c === 'UYE' || c === 'У.Е.' || c === 'УЕ') return 'USD';
  return code;
}

function detectAgency(item) {
  // Top-level boolean on every OLX portal: true = business/agency account.
  if (typeof item.business === 'boolean') return item.business;
  return Boolean(item.shop) || item.user?.is_business === true;
}

function mapItem(item, country) {
  const params = paramMap(item);
  const priceParam = params.price?.value;
  // Rooms: prefer OLX's structured `rooms` param. Fall back to the title, but
  // only match an explicit room word — NEVER a bare "кв" (that is "кв.м" area or
  // "квартал" block, e.g. "72 кв.м" is 72 m², not 72 rooms). Allow the Russian
  // "2х-комнатная" / "2-комн" filler between the number and the word.
  const roomsFromTitle = (item.title || '').match(
    /(\d+)\s*[-хx]?\s*(?:camer|комнатн|комн|кімнат|кімн|room|bedroom|xonali|xona)/i,
  );
  let rooms =
    Number(params.rooms?.value?.key) ||
    Number((params.rooms?.value?.label || '').match(/\d+/)?.[0]) ||
    (roomsFromTitle ? Number(roomsFromTitle[1]) : null) ||
    null;
  // Sanity cap: dwellings realistically have 1–10 rooms; larger is a mis-parse.
  if (rooms != null && (rooms < 1 || rooms > 10)) rooms = null;
  const area =
    Number(params.m?.value?.key) ||
    Number((params.m?.value?.label || '').match(/\d+/)?.[0]) ||
    null;

  // Classification is intrinsic listing data. Never copy the currently
  // selected UI filter into a row: doing that turned every result from a
  // `propertyType=house` scrape into a house (including apartments). Include
  // OLX category/parameter labels when available, as titles alone are often
  // too terse to identify the dwelling type.
  const categoryText = [
    item.category?.name,
    item.category?.label,
    ...Object.values(params).flatMap((param) => [param?.name, param?.value?.label]),
  ].filter(Boolean).join(' ');
  const propertyType = guessPropertyType(`${item.title || ''} ${categoryText}`);

  return makeListing({
    id: item.id,
    source: 'olx',
    country: country.code,
    title: item.title,
    description: item.description ?? '',
    propertyType,
    byAgency: detectAgency(item),
    price: priceParam?.value ?? null,
    currency: normalizeCurrency(priceParam?.currency) ?? country.currency,
    rooms,
    areaSqm: area,
    city: item.location?.city?.name ?? item.location?.region?.name ?? '',
    lat: item.map?.lat ?? null,
    lng: item.map?.lon ?? null,
    photos: allPhotos(item),
    url: item.url ?? country.olxHost,
    createdAt: item.created_time ?? null,
  });
}

// Re-fetch a single OLX offer by id (used by the manual "reload this listing"
// action). OLX exposes each offer at /api/v1/offers/{id}/. Returns a freshly
// mapped listing, or null if the offer no longer exists.
export async function fetchOlxOffer(country, id) {
  const url = `${country.olxHost}/api/v1/offers/${encodeURIComponent(id)}/`;
  const res = await olxFetch(country, url);
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`OLX ${country.code} offer HTTP ${res.status}`);
  const json = await res.json();
  const item = json?.data;
  if (!item || typeof item !== 'object') return null;
  return mapItem(item, country);
}

// One rate-limited GET to an OLX portal. Honors a 429 by backing off (Retry-After
// if the portal sends it, else OLX_BACKOFF_MS) before surfacing the error so the
// caller can decide whether to retry.
async function olxFetch(country, url) {
  await throttle(`olx:${country.olxHost}`, OLX_MIN_INTERVAL_MS, OLX_JITTER_MS);
  const res = await fetch(url, {
    headers: browserHeaders(country),
    signal: AbortSignal.timeout(12_000),
  });
  if (res.status === 429) {
    const retryAfter = Number(res.headers.get('retry-after'));
    await sleep(Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : OLX_BACKOFF_MS);
    throw new Error(`OLX ${country.code} HTTP 429`);
  }
  return res;
}

// Scrape one country's real-estate snapshot via the fetcher sidecar. The caller
// (index.js) neutralizes UI filters, so we fetch the whole category newest-first
// and let applyFilters narrow it in memory afterwards — `filters` is unused here.
export async function scrapeOlx(country, _filters) {
  if (!OLX_FETCHER_URL) return []; // OLX disabled until the fetch sidecar is set
  const out = [];
  const seen = new Set();
  for (let page = 1; page <= OLX_MAX_PAGES; page++) {
    let ads;
    try {
      ads = await fetchStatePage(country, page);
    } catch (err) {
      if (page === 1) throw err; // first page must succeed (caller falls back to mock)
      break; // later-page hiccup: keep what we already have
    }
    if (!ads.length) break;
    for (const item of ads) {
      if (item?.id == null || seen.has(item.id)) continue;
      seen.add(item.id);
      out.push(mapStateItem(item, country));
    }
    if (ads.length < 40) break; // short page → end of results
  }
  return out;
}
