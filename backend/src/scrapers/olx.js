// OLX adapter.
//
// OLX's own web frontend talks to an internal JSON endpoint:
//   {host}/api/v1/offers/?offset=&limit=&category_id=&query=&filter_float_price:from=&...
// It is far more stable than parsing HTML, so we use it directly. We keep the
// request defensive: any network error, block, or shape change throws and the
// caller falls back to demo data.

import { makeListing } from '../normalize.js';

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

function firstPhoto(item) {
  const link = item.photos?.[0]?.link;
  if (!link) return null;
  return link.replace('{width}', '600').replace('{height}', '400');
}

function detectAgency(item) {
  // Top-level boolean on every OLX portal: true = business/agency account.
  if (typeof item.business === 'boolean') return item.business;
  return Boolean(item.shop) || item.user?.is_business === true;
}

export async function scrapeOlx(country, filters) {
  const url = buildUrl(country, filters);
  const res = await fetch(url, {
    headers: { 'User-Agent': UA_HEADER, Accept: 'application/json', 'Accept-Language': 'en' },
    signal: AbortSignal.timeout(12_000),
  });
  if (!res.ok) throw new Error(`OLX ${country.code} HTTP ${res.status}`);
  const json = await res.json();
  const data = json?.data;
  if (!Array.isArray(data)) throw new Error(`OLX ${country.code} unexpected payload`);

  return data.map((item) => {
    const params = paramMap(item);
    const priceParam = params.price?.value;
    const rooms =
      Number(params.rooms?.value?.key) ||
      Number((params.rooms?.value?.label || '').match(/\d+/)?.[0]) ||
      Number((item.title || '').match(/(\d+)\s*-?\s*(camer|комн|кімн|room|кв)/i)?.[1]) ||
      null;
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
      currency: priceParam?.currency ?? country.currency,
      rooms,
      areaSqm: area,
      city: item.location?.city?.name ?? item.location?.region?.name ?? '',
      lat: item.map?.lat ?? null,
      lng: item.map?.lon ?? null,
      photo: firstPhoto(item),
      url: item.url ?? country.olxHost,
      createdAt: item.created_time ?? null,
    });
  });
}
