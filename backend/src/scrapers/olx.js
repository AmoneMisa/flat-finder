// OLX adapter.
//
// OLX's own web frontend talks to an internal JSON endpoint:
//   {host}/api/v1/offers/?offset=&limit=&category_id=&query=&filter_float_price:from=&...
// It is far more stable than parsing HTML, so we use it directly. We keep the
// request defensive: any network error, block, or shape change throws and the
// caller falls back to demo data.

import { makeListing } from '../normalize.js';

// Pull several newest-first pages so enough recent listings survive the 3-week
// freshness filter. One page (~50) is far too few for big markets.
const OLX_PAGE_SIZE = 50;
const OLX_MAX_PAGES = 10; // hard ceiling (~500 fetched) to bound latency

const UA_HEADER =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

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

function mapItem(item, country, filters) {
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

  // OLX only tells us category.type === 'real_estate', so classify flat vs
  // house from the listing title. Honor an explicit filter first.
  const t = (item.title || '').toLowerCase();
  const isHouse = /cas[aă]|дом|будин|house|коттедж|вилл/.test(t);
  let propertyType = 'flat';
  if (filters.propertyType === 'house' || filters.propertyType === 'flat')
    propertyType = filters.propertyType;
  else if (isHouse) propertyType = 'house';

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

async function fetchPage(country, filters, offset) {
  const url = buildUrl(country, { ...filters, offset, limit: OLX_PAGE_SIZE });
  const res = await fetch(url, {
    headers: { 'User-Agent': UA_HEADER, Accept: 'application/json', 'Accept-Language': 'en' },
    signal: AbortSignal.timeout(12_000),
  });
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
    for (const item of data) out.push(mapItem(item, country, filters));

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
