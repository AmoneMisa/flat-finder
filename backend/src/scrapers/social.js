import { makeListing } from '../normalize.js';
import { MAX_AGE_MS } from '../listing-policy.js';
import {
  parsePriceFromText,
  parseRoomsFromText,
  parseAreaFromText,
  guessPropertyType,
  classifyAgency,
  looksHousingWanted,
} from '../textparse.js';

const SOCIAL_FETCHER_URL = String(process.env.SOCIAL_FETCHER_URL || '').replace(/\/$/, '');
const SOCIAL_TIMEOUT_MS = Math.max(30_000, Math.min(170_000, Number(process.env.SOCIAL_HOUSING_TIMEOUT_MS) || 150_000));
const SOCIAL_LIMIT = Math.max(5, Math.min(100, Number(process.env.SOCIAL_HOUSING_LIMIT) || 40));

const HOUSING_RE = /(apartament|apartment|flat|casa|locuin|imobil|camer[ăa]|квартир|kvartira|\bkv\b|дом|\buy\b|будин|пәтер|үй|кімнат|комнат|xona|ijara|arenda|аренд|оренд|жал[гғ]а|rent|închiri|inchiri|сдам|здам|сдаю|здаю|сдается|сдається|beriladi|sotiladi|прода[её]т|продаю|продаж|sale|vând|vand|vânzare|vanzare|m2|м2|кв\.?\s?м|\$|€|грн|сум|so'?m|тенге|у\.?е)/iu;
const SALE_RE = /(прода[её]т|продаю|продам|продаж|sale|for sale|sotiladi|sotuv|vând|vand|vânzare|vanzare|de\s+v[âa]nzare)/iu;
const SHORT_RE = /(посуточн|суточн|подобов|daily rent|short[- ]?term|regim hotelier|kunlik|sutkaga)/iu;
const OFFER_RE = /(сдам|сдаю|сдается|сдається|здам|здаю|здається|аренд|оренд|ijara(?:ga)?|beriladi|rent|for rent|închiriez|inchiriez|de\s+închiriat|de\s+inchiriat|жал[гғ]а(?:\s+беріледі)?|прода[её]т|продаю|продам|продаж|sale|sotiladi|sotuv|vând|vand|vânzare|vanzare|de\s+v[âa]nzare)/iu;
const WANTED_RE = /(?:ищу|сниму|хочу\s+снять|куплю|нужн[ао]\s+(?:квартир|комнат|дом)|шукаю|зніму|хочу\s+орендувати|потрібн[ао]\s+(?:квартир|кімнат|будин)|caut\s+(?:s[ăa]\s+închiriez|sa\s+inchiriez|apartament|cas[ăa]|camer[ăa]|locuin)|vreau\s+s[ăa]\s+(?:închiriez|cumpăr)|пәтер\s+іздеймін|үй\s+іздеймін|kvartira\s+(?:kerak|qidir)|uy\s+(?:kerak|qidir))/iu;

function socialTarget(value) {
  if (typeof value === 'string') return { target: value, city: null, dealType: null };
  if (value && typeof value === 'object') {
    return {
      target: String(value.target || value.url || value.query || '').trim(),
      city: value.city ? String(value.city) : null,
      dealType: value.dealType ? String(value.dealType) : null,
    };
  }
  return null;
}

export function classifyHousingOffer(text, forced = null) {
  const value = String(text || '').replace(/[ \t]+/g, ' ').trim();
  if (value.length < 12 || !HOUSING_RE.test(value)) return null;
  if (WANTED_RE.test(value) || looksHousingWanted(value)) return null;
  if (!OFFER_RE.test(value)) return null;
  if (forced) return forced;
  if (SHORT_RE.test(value)) return 'shortRent';
  if (SALE_RE.test(value)) return 'sale';
  return 'longRent';
}

function itemToListing(item, source, targetConfig, country) {
  const text = String(item?.text || '').replace(/[ \t]+/g, ' ').trim();
  const dealType = classifyHousingOffer(text, targetConfig.dealType);
  if (!dealType) return null;

  const createdAt = item?.createdAt || null;
  if (createdAt) {
    const ts = Date.parse(createdAt);
    if (Number.isFinite(ts) && Date.now() - ts > MAX_AGE_MS) return null;
  }

  const { price, currency } = parsePriceFromText(text, country.currency);
  const id = String(item?.id || item?.url || '').trim();
  if (!id) return null;

  return makeListing({
    id: `${source}-${id}`,
    source,
    country: country.code,
    title: text.split('\n')[0].slice(0, 90),
    description: text,
    propertyType: guessPropertyType(text),
    byAgency: classifyAgency(text),
    price,
    currency,
    rooms: parseRoomsFromText(text),
    areaSqm: parseAreaFromText(text),
    city: targetConfig.city,
    lat: null,
    lng: null,
    photos: Array.isArray(item?.images) ? item.images.filter(Boolean) : [],
    dealType,
    url: item?.url || targetConfig.target,
    createdAt,
  });
}

async function fetchSocial(path, body) {
  if (!SOCIAL_FETCHER_URL) throw new Error('SOCIAL_FETCHER_URL is not configured');
  const response = await fetch(`${SOCIAL_FETCHER_URL}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(SOCIAL_TIMEOUT_MS),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload?.ok === false) {
    throw new Error(payload?.error || `social-fetcher HTTP ${response.status}`);
  }
  return Array.isArray(payload?.items) ? payload.items : [];
}

async function scrapeTargets(country, source, values) {
  const configs = (values || []).map(socialTarget).filter((value) => value?.target);
  const listings = [];
  const errors = [];
  let rawItems = 0;
  let recentItems = 0;
  let rejectedDemand = 0;

  for (const config of configs) {
    try {
      const items = source === 'threads'
        ? await fetchSocial('/threads/search', { query: config.target, limit: SOCIAL_LIMIT })
        : await fetchSocial('/fetch', { source: 'facebook', target: config.target, limit: SOCIAL_LIMIT });

      rawItems += items.length;
      for (const item of items) {
        const text = String(item?.text || '');
        if (WANTED_RE.test(text) || looksHousingWanted(text)) rejectedDemand += 1;
        const ts = item?.createdAt ? Date.parse(item.createdAt) : NaN;
        if (!Number.isFinite(ts) || Date.now() - ts <= MAX_AGE_MS) recentItems += 1;
        const listing = itemToListing(item, source, config, country);
        if (listing) listings.push(listing);
      }
    } catch (error) {
      const message = error?.message || String(error);
      errors.push({ target: config.target, error: message });
      console.warn(`[${source}:housing] ${config.target}: ${message}`);
    }
  }

  const complete = errors.length === 0 && (configs.length === 0 || rawItems > 0);

  return {
    listings,
    complete,
    partialExpected: !complete,
    errors,
    rawItems,
    diagnostics: {
      fetched: rawItems,
      recent: recentItems,
      classified: listings.length,
      rejectedDemand,
    },
    processedTargets: configs.map((config) => config.target),
  };
}

export async function scrapeFacebook(country) {
  return scrapeTargets(country, 'facebook', country.facebookHousingTargets);
}

export async function scrapeThreads(country) {
  return scrapeTargets(country, 'threads', country.threadsHousingQueries);
}
