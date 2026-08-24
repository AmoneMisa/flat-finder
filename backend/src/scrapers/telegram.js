// Telegram adapter. Public Telegram *channels* are read through the MTProto
// sidecar worker (see telegram-worker/), which logs in as a real user account
// and calls messages.getHistory. This replaced scraping https://t.me/s/<channel>
// because Telegram heavily throttles that web preview from datacenter IPs (a
// production server saw ~1 post where a browser sees hundreds). The worker is
// transport-only: it returns raw message text/date, and all the housing
// parsing/filtering below stays here so there's a single source of truth.

import {makeListing} from '../normalize.js';
import {MAX_AGE_MS} from '../listing-policy.js';
import {looksTelegramRoomShare} from '../telegram-room-share.js';
import {
  parsePriceFromText,
  parseRoomsFromText,
  parseAreaFromText,
  guessPropertyType,
  classifyAgency,
  looksHousingWanted,
} from '../textparse.js';

const TG_WORKER_URL = process.env.TG_WORKER_URL || '';

const HOUSING_RE =
  /(apartament|casa|квартир|kvartira|\bkv\b|дом|\buy|будин|пәтер|үй|кімнат|комнат|xona|ijara|arenda|аренд|жал[гғ]а|m2|м2|кв\.?\s?м|\$|€|грн|сум|so'?m|тенге|у\.?е)/i;

const TELEGRAM_DIRECT_OWNER_RE =
  /(?:makler\s*[- ]?siz|maklersiz|bez\s*makler(?:a|ov)?|bezmakler(?:a|ov)?|vositachi\s*[- ]?siz|vositachisiz|egasidan|uy\s+egasidan|без\s+(?:макл(?:ер[а-яё]*)?|посредник[а-яё]*|ри[еэ]?лтор[а-яё]*|агент[а-яё]*)|от\s+(?:собственник[а-яё]*|хозяин[а-яё]*)|owner\s+direct|direct\s+from\s+(?:owner|landlord))/iu;

const TELEGRAM_BARE_USD_RE =
  /^.{0,70}?(?<![\d+])([1-9]\d{2,3})(?!\d)(?=\s+(?!m2\b|m²\b|м2\b|м²\b|qavat\b|этаж\b|xona\b|xonali\b|комнат\b|kvartal\b|квартал\b)[\p{L}])/iu;

export function classifyTelegramAgency(text) {
  if (!text) return false;
  if (TELEGRAM_DIRECT_OWNER_RE.test(text)) return false;
  return classifyAgency(text);
}

export function guessTelegramPropertyType(text) {
  if (!text) return 'flat';
  if (/(?:^|[^\p{L}\p{N}_])[xh]ovli(?:ni|da|dan|ning)?(?=$|[^\p{L}\p{N}_])/iu.test(text)) {
    return 'house';
  }
  return guessPropertyType(text);
}

export function parseTelegramPrice(text, country, dealType = null) {
  const fallbackCurrency = country?.currency || '';
  const parsed = parsePriceFromText(text, fallbackCurrency);
  if (parsed.price != null) return parsed;

  const value = String(text || '');
  const isUzbek = String(country?.code || '').toUpperCase() === 'UZ';
  const explicitlySale = dealType === 'sale' ||
    /(?:sotiladi|sotuv|sotaman|прода[её]тся|продам|продажа|for\s+sale|\bsale\b)/iu.test(value);
  if (!isUzbek || explicitlySale) return parsed;

  // Most configured Uzbek Telegram feeds are rental feeds but do not carry a
  // dealType flag. A 3-4 digit bare amount at the start is therefore accepted
  // as USD when the post itself still looks like housing. Sale language above
  // is an explicit veto, and the regexp excludes area/floor/room/block labels.
  const rentalOrHousing = dealType === 'longRent' || dealType === 'shortRent' ||
    /(?:ijara|ijaraga|arenda|аренд|сдам|сда[её]тся|rent\b|xona|xonali|kvartira|uy\b|[xh]ovli)/iu.test(value);
  if (!rentalOrHousing) return parsed;

  const head = value.slice(0, 100);
  const match = head.match(TELEGRAM_BARE_USD_RE);
  if (!match) return parsed;

  const price = Number(match[1]);
  if (!Number.isFinite(price) || price < 100 || price > 9999) return parsed;

  return {price, currency: 'USD'};
}

function messageToListing(msg, channelConfig, country) {
  const channel = channelConfig.name;
  const text = (msg.text || '').replace(/[ \t]+/g, ' ').trim();

  if (looksHousingWanted(text)) return null;
  if (text.length < 10) return null;
  if (!HOUSING_RE.test(text)) return null;

  const {price, currency} = parseTelegramPrice(text, country, channelConfig.dealType);
  const type = guessTelegramPropertyType(text);
  const byAgency = classifyTelegramAgency(text);
  const title = text.split('\n')[0].slice(0, 90);
  const postPath = `${channel}/${msg.id}`;

  const photoIds = Array.isArray(msg.photoIds) && msg.photoIds.length
    ? msg.photoIds
    : msg.hasPhoto ? [msg.id] : [];
  const photos = photoIds.map((pid) => `/api/tg-photo/${channel}/${pid}`);
  const photoFingerprints = [
    ...new Set(
      (Array.isArray(msg.photoFingerprints) ? msg.photoFingerprints : [])
        .map((value) => String(value || '').toLowerCase())
        .filter((value) => /^[a-f0-9]{64}$/.test(value)),
    ),
  ].sort();

  return makeListing({
    id: `tg-${channel}-${postPath}`,
    source: 'telegram',
    country: country.code,
    title,
    description: text,
    propertyType: type,
    roomOnly: looksTelegramRoomShare(text) ? true : undefined,
    byAgency,
    commission: byAgency ? undefined : false,
    commissionPercent: byAgency ? undefined : 0,
    price,
    currency,
    rooms: parseRoomsFromText(text),
    areaSqm: parseAreaFromText(text),
    city: channelConfig.city ?? null,
    lat: null,
    lng: null,
    photos,
    photoFingerprints,
    photoFingerprintKey: photoFingerprints.length >= 2 ? photoFingerprints.join('|') : null,
    dealType: channelConfig.dealType ?? null,
    url: `https://t.me/${postPath}`,
    createdAt: msg.date,
  });
}

async function fetchWorkerPage(channel, beforeId, deadline) {
  const params = new URLSearchParams({channel, limit: '100'});
  if (beforeId) params.set('beforeId', String(beforeId));
  const budgetLeft = deadline === Infinity ? 15_000 : Math.max(1_000, deadline - Date.now());
  const res = await fetch(`${TG_WORKER_URL}/history?${params}`, {
    signal: AbortSignal.timeout(Math.min(15_000, budgetLeft)),
  });
  if (!res.ok) throw new Error(`tg-worker @${channel} HTTP ${res.status}`);
  const body = await res.json();
  if (!body.ok) throw new Error(body.error || `tg-worker @${channel} error`);
  return body;
}

const TG_MAX_PAGES = 8;

export async function fetchChannel(channelConfig, country, filters = {}, deadline = Infinity) {
  const channel = channelConfig.name;
  const listings = [];
  let beforeId = 0;

  for (let page = 0; page < TG_MAX_PAGES; page++) {
    if (Date.now() >= deadline) break;

    const {messages, minId} = await fetchWorkerPage(channel, beforeId, deadline);
    if (!messages.length && minId === null) break;

    let oldestTs = null;
    for (const message of messages) {
      const listing = messageToListing(message, channelConfig, country);
      if (listing) listings.push(listing);

      if (message.date) {
        const time = Date.parse(message.date);
        if (!Number.isNaN(time)) {
          oldestTs = oldestTs === null ? time : Math.min(oldestTs, time);
        }
      }
    }

    if (minId === null || minId === beforeId) break;
    if (oldestTs && Date.now() - oldestTs > MAX_AGE_MS) break;
    beforeId = minId;
  }

  return listings;
}

async function fetchChannelWithRetry(channelConfig, country, filters, deadline = Infinity) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const result = await fetchChannel(channelConfig, country, filters, deadline);
      if (result.length > 0 || attempt === 1) return result;
    } catch (err) {
      if (attempt === 1) {
        console.warn(`[telegram] @${channelConfig.name}: ${err?.message ?? err}`);
        return [];
      }
    }

    if (Date.now() >= deadline) return [];
    await new Promise((resolve) => setTimeout(resolve, 500));
  }

  return [];
}

const TG_BUDGET_MS = Number(process.env.TG_BUDGET_MS) || 12000;
const telegramChannelCursor = new Map();
const TG_CHANNELS_PER_RUN = Math.max(1, Number(process.env.TG_CHANNELS_PER_RUN) || 6);

function selectTelegramChannels(country) {
  const all = (country.telegramChannels ?? []).map(normalizeChannelConfig).filter(Boolean);
  if (all.length <= TG_CHANNELS_PER_RUN) {
    return {channels: all, complete: true};
  }

  let start = telegramChannelCursor.get(country.code);
  if (!Number.isInteger(start)) {
    start = (Math.floor(Date.now() / 60_000) * TG_CHANNELS_PER_RUN) % all.length;
  }

  const selected = [];
  for (let index = 0; index < TG_CHANNELS_PER_RUN; index += 1) {
    selected.push(all[(start + index) % all.length]);
  }

  telegramChannelCursor.set(
    country.code,
    (start + TG_CHANNELS_PER_RUN) % all.length,
  );

  return {channels: selected, complete: false};
}

export async function scrapeTelegram(country, filters) {
  if (!TG_WORKER_URL) throw new Error('TG_WORKER_URL is not configured');

  const {channels, complete} = selectTelegramChannels(country);
  const CONCURRENCY = 4;
  const deadline = Date.now() + TG_BUDGET_MS;
  const listings = [];

  for (let index = 0; index < channels.length; index += CONCURRENCY) {
    if (Date.now() >= deadline) break;

    const batch = channels.slice(index, index + CONCURRENCY);
    const results = await Promise.allSettled(
      batch.map((channel) => fetchChannelWithRetry(channel, country, filters, deadline)),
    );

    for (const result of results) {
      if (result.status === 'fulfilled') listings.push(...result.value);
    }
  }

  return {
    listings,
    complete,
    partialExpected: !complete,
    processedChannels: channels.map((channel) => channel.name),
  };
}

function normalizeChannelConfig(value) {
  if (typeof value === 'string') {
    return {name: value, city: null, dealType: null};
  }

  if (value && typeof value === 'object' && value.name) {
    return {
      name: String(value.name),
      city: value.city ? String(value.city) : null,
      dealType: value.dealType ? String(value.dealType) : null,
    };
  }

  return null;
}
