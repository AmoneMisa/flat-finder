// OLX adapter.
//
// OLX's own web frontend talks to an internal JSON endpoint:
//   {host}/api/v1/offers/?offset=&limit=&category_id=&query=&filter_float_price:from=&...
// It is far more stable than parsing HTML, so we use it directly. We keep the
// request defensive: any network error, block, or shape change throws and the
// caller falls back to demo data.

import { makeListing } from '../normalize.js';
import { guessPropertyType } from '../textparse.js';
import { throttle, sleep } from '../ratelimit.js';

// Pull several newest-first pages so enough recent listings survive the 3-week
// freshness filter. One page (~50) is far too few for big markets.
const OLX_PAGE_SIZE = 50;
const OLX_MAX_PAGES = 10; // hard ceiling (~500 fetched) to bound latency

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

function buildUrl(country, filters) {
  const host = country.olxHost;
  const p = new URLSearchParams();
  p.set('offset', String(filters.offset ?? 0));
  p.set('limit', String(filters.limit ?? 40));

  // Scope to the portal's real-estate section.
  if (country.realEstateRoot) p.set('category_id', String(country.realEstateRoot));

  // Narrow flat vs house with a localized term (OLX has no single stable
  // sub-category id across portals). Combine with any free-text query.
  const type = filters.propertyType;
  const terms = [];
  if (type === 'flat' || type === 'house') terms.push(country.terms?.[type] ?? '');
  const deal = filters.dealType;
  if (deal === 'sale' || deal === 'longRent' || deal === 'shortRent')
    terms.push(country.dealTerms?.[deal] ?? '');
  if (filters.query) terms.push(filters.query);
  if (terms.length) p.set('query', terms.filter(Boolean).join(' '));

  if (filters.priceMin != null) p.set('filter_float_price:from', String(filters.priceMin));
  if (filters.priceMax != null) p.set('filter_float_price:to', String(filters.priceMax));

  // Newest first: OLX's default ordering mixes in old listings, most of which
  // the 3-week freshness filter later drops. Sorting by creation date keeps the
  // fetched batch recent so far more of it survives.
  p.set('sort_by', 'created_at:desc');

  // NB: the owner/agency (filter_enum_business) filter is rejected at the
  // real-estate root category on some portals, so we enforce it after
  // normalization via applyFilters() using each offer's `business` flag.

  return `${host}/api/v1/offers/?${p.toString()}`;
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

async function fetchPage(country, filters, offset) {
  const url = buildUrl(country, { ...filters, offset, limit: OLX_PAGE_SIZE });
  const res = await olxFetch(country, url);
  if (!res.ok) throw new Error(`OLX ${country.code} HTTP ${res.status}`);
  const json = await res.json();
  const data = json?.data;
  if (!Array.isArray(data)) throw new Error(`OLX ${country.code} unexpected payload`);
  return data;
}

export async function scrapeOlx(country, filters) {
  const out = [];
  for (let page = 0; page < OLX_MAX_PAGES; page++) {
    let data;
    try {
      data = await fetchPage(country, filters, page * OLX_PAGE_SIZE);
    } catch (err) {
      if (page === 0) throw err; // first page must succeed (caller falls back to mock)
      break; // later-page hiccup: keep what we already have
    }
    for (const item of data) out.push(mapItem(item, country));

    // Only stop on a genuinely short page (end of results). We deliberately do
    // NOT early-stop on an old last item: OLX ignores `sort_by=created_at:desc`,
    // so results come back in mixed date order and each page carries roughly a
    // third of fresh (<31d) listings. Stopping on an old tail therefore threw
    // away the fresh listings still sitting on later pages. Paging the full
    // budget and letting the freshness filter do the trimming yields far more.
    if (data.length < OLX_PAGE_SIZE) break;
  }
  return out;
}
