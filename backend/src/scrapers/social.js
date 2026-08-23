import { makeListing, MAX_AGE_MS } from '../normalize.js';
import {
  parsePriceFromText,
  parseRoomsFromText,
  parseAreaFromText,
  guessPropertyType,
  classifyAgency,
  looksHousingWanted,
} from '../textparse.js';

const SOCIAL_FETCHER_URL = String(process.env.SOCIAL_FETCHER_URL || '').replace(/\/$/, '');
const SOCIAL_TIMEOUT_MS = Math.max(5_000, Number(process.env.SOCIAL_HOUSING_TIMEOUT_MS) || 45_000);
const SOCIAL_LIMIT = Math.max(5, Math.min(100, Number(process.env.SOCIAL_HOUSING_LIMIT) || 40));

const HOUSING_RE = /(apartament|apartment|flat|casa|квартир|kvartira|\bkv\b|дом|\buy\b|будин|пәтер|үй|кімнат|комнат|xona|ijara|arenda|аренд|оренд|жал[гғ]а|rent|inchiri|сдам|сдаю|сдается|сдається|beriladi|sotiladi|прода[её]т|продаж|sale|m2|м2|кв\.?\s?м|\$|€|грн|сум|so'?m|тенге|у\.?е)/i;
const SALE_RE = /(прода[её]т|продаж|продам|sale|for sale|sotiladi|sotuv|de vanzare)/i;
const SHORT_RE = /(посуточн|суточн|подобов|daily rent|short[- ]?term|regim hotelier|kunlik|sutkaga)/i;
const OFFER_RE = /(сдам|сдаю|сдается|сдається|аренд|оренд|ijara|ijaraga|beriladi|rent|for rent|inchiri|жал[гғ]а|прода[её]т|продам|продаж|sale|sotiladi|sotuv)/i;

function socialTarget(value) {
  if (typeof value === 'string') {
    return { target: value, city: null, dealType: null };
  }
  if (value && typeof value === 'object') {
    return {
      target: String(value.target || value.url || value.query || '').trim(),
      city: value.city ? String(value.city) : null,
      dealType: value.dealType ? String(value.dealType) : null,
    };
  }
  return null;
}

function detectDealType(text, forced = null) {
  if (forced) return forced;
  if (SHORT_RE.test(text)) return 'shortRent';
  if (SALE_RE.test(text)) return 'sale';
  return 'longRent';
}

function itemToListing(item, source, targetConfig, country) {
  const text = String(item?.text || '').replace(/[ \t]+/g, ' ').trim();
  if (text.length < 12) return null;
  if (!HOUSING_RE.test(text) || !OFFER_RE.test(text)) return null;
  if (looksHousingWanted(text)) return null;

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
    dealType: detectDealType(text, targetConfig.dealType),
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

  for (const config of configs) {
    try {
      const items = source === 'threads'
        ? await fetchSocial('/threads/search', { query: config.target, limit: SOCIAL_LIMIT })
        : await fetchSocial('/fetch', { source: 'facebook', target: config.target, limit: SOCIAL_LIMIT });

      for (const item of items) {
        const listing = itemToListing(item, source, config, country);
        if (listing) listings.push(listing);
      }
    } catch (error) {
      const message = error?.message || String(error);
      errors.push({ target: config.target, error: message });
      console.warn(`[${source}:housing] ${config.target}: ${message}`);
    }
  }

  return {
    listings,
    // A partial social crawl must never age-out rows from targets that failed in
    // this pass. Deactivation is safe only after every configured target replied.
    complete: errors.length === 0,
    partialExpected: errors.length > 0,
    errors,
    processedTargets: configs.map((config) => config.target),
  };
}

export async function scrapeFacebook(country) {
  return scrapeTargets(country, 'facebook', country.facebookHousingTargets);
}

export async function scrapeThreads(country) {
  return scrapeTargets(country, 'threads', country.threadsHousingQueries);
}
