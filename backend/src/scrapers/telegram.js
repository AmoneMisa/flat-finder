// Telegram adapter. Public Telegram *channels* are read through the MTProto
// sidecar worker (see telegram-worker/), which logs in as a real user account
// and calls messages.getHistory. This replaced scraping https://t.me/s/<channel>
// because Telegram heavily throttles that web preview from datacenter IPs (a
// production server saw ~1 post where a browser sees hundreds). The worker is
// transport-only: it returns raw message text/date, and all the housing
// parsing/filtering below stays here so there's a single source of truth.

import { makeListing, MAX_AGE_MS } from '../normalize.js';
import {
  parsePriceFromText,
  parseRoomsFromText,
  parseAreaFromText,
  guessPropertyType,
  classifyAgency,
} from '../textparse.js';

// Base URL of the MTProto worker (set in docker-compose). When unset the
// telegram source simply yields nothing, so the backend is not hard-coupled to
// the worker being up — OLX and the other sources still return results.
const TG_WORKER_URL = process.env.TG_WORKER_URL || '';

// Only keep messages that look like housing posts. Covers RU/UA/RO plus Uzbek
// (uy/kvartira/xona/ijara) and Kazakh (пәтер/үй/жалға).
const HOUSING_RE =
  /(apartament|casa|квартир|kvartira|\bkv\b|дом|\buy|будин|пәтер|үй|кімнат|комнат|xona|ijara|arenda|аренд|жал[гғ]а|m2|м2|кв\.?\s?м|\$|€|грн|сум|so'?m|тенге|у\.?е)/i;

// Turn one worker message ({ id, text, date, hasPhoto }) into a listing, or
// null if it isn't a housing post (or is filtered out by the keyword query).
function messageToListing(msg, channel, country, filters) {
  const text = (msg.text || '').replace(/[ \t]+/g, ' ').trim();
  if (text.length < 10) return null;
  if (!HOUSING_RE.test(text)) return null;
  if (filters.query && !text.toLowerCase().includes(filters.query.toLowerCase())) return null;

  const { price, currency } = parsePriceFromText(text, country.currency);
  const type =
    filters.propertyType === 'house' || filters.propertyType === 'flat'
      ? filters.propertyType
      : guessPropertyType(text);
  const title = text.split('\n')[0].slice(0, 90);
  const postPath = `${channel}/${msg.id}`;

  // Every image in the post (albums share a groupedId in the worker) becomes a
  // relative photo-proxy URL. Fall back to the single caption-message id for
  // older worker builds that don't send photoIds.
  const photoIds =
    Array.isArray(msg.photoIds) && msg.photoIds.length
      ? msg.photoIds
      : msg.hasPhoto
        ? [msg.id]
        : [];
  const photos = photoIds.map((pid) => `/api/tg-photo/${channel}/${pid}`);

  return makeListing({
    id: `tg-${channel}-${postPath}`,
    source: 'telegram',
    country: country.code,
    title,
    description: text,
    propertyType: type,
    // No structured business flag in Telegram — infer realtor/agency from text.
    byAgency: classifyAgency(text),
    price,
    currency,
    rooms: parseRoomsFromText(text),
    areaSqm: parseAreaFromText(text),
    city: `@${channel}`,
    lat: null,
    lng: null,
    // Relative paths to the backend photo proxy, which pulls each image from the
    // MTProto worker on demand. The app resolves them against its API base.
    // Empty when the post has no photo so the app shows its placeholder.
    photos,
    url: `https://t.me/${postPath}`,
    createdAt: msg.date,
  });
}

// Fetch one history page from the worker. Returns the parsed messages plus the
// smallest message id seen (the `beforeId` cursor for paging to older posts).
async function fetchWorkerPage(channel, beforeId, deadline) {
  const params = new URLSearchParams({ channel, limit: '100' });
  if (beforeId) params.set('beforeId', String(beforeId));
  // Cap the per-request wait by whatever budget remains, so a slow worker call
  // can't overrun the outer telegram budget.
  const budgetLeft = deadline === Infinity ? 15_000 : Math.max(1_000, deadline - Date.now());
  const res = await fetch(`${TG_WORKER_URL}/history?${params}`, {
    signal: AbortSignal.timeout(Math.min(15_000, budgetLeft)),
  });
  if (!res.ok) throw new Error(`tg-worker @${channel} HTTP ${res.status}`);
  const body = await res.json();
  if (!body.ok) throw new Error(body.error || `tg-worker @${channel} error`);
  return body;
}

// The worker returns up to 100 messages per call; page back via the `beforeId`
// cursor to cover the full freshness window. The early-stop keeps dead channels
// cheap (bail as soon as a page is entirely older than MAX_AGE_MS).
const TG_MAX_PAGES = 8;

export async function fetchChannel(channel, country, filters = {}, deadline = Infinity) {
  const listings = [];
  let beforeId = 0;
  for (let page = 0; page < TG_MAX_PAGES; page++) {
    if (Date.now() >= deadline) break;
    const { messages, minId } = await fetchWorkerPage(channel, beforeId, deadline);
    if (!messages.length && minId === null) break; // end of history

    let oldestTs = null;
    for (const m of messages) {
      const l = messageToListing(m, channel, country, filters);
      if (l) listings.push(l);
      if (m.date) {
        const t = Date.parse(m.date);
        if (!Number.isNaN(t)) oldestTs = oldestTs === null ? t : Math.min(oldestTs, t);
      }
    }

    // Cursor didn't advance -> nothing older to fetch.
    if (minId === null || minId === beforeId) break;
    // Every post on this page is older than the freshness window: stop paging.
    if (oldestTs && Date.now() - oldestTs > MAX_AGE_MS) break;
    beforeId = minId;
  }
  return listings;
}

// Fetch a channel with one retry, mirroring the previous adapter's resilience.
async function fetchChannelWithRetry(channel, country, filters, deadline = Infinity) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const r = await fetchChannel(channel, country, filters, deadline);
      if (r.length > 0 || attempt === 1) return r;
    } catch (err) {
      if (attempt === 1) return [];
    }
    if (Date.now() >= deadline) return [];
    await new Promise((r) => setTimeout(r, 500));
  }
  return [];
}

// Wall-clock budget for a whole telegram scrape, so one slow channel can't blow
// past the nginx proxy timeout and starve the fast OLX results.
const TG_BUDGET_MS = Number(process.env.TG_BUDGET_MS) || 12000;

export async function scrapeTelegram(country, filters) {
  if (!TG_WORKER_URL) {
    throw new Error('TG_WORKER_URL is not configured');
  }
  const channels = country.telegramChannels ?? [];
  // The worker serializes MTProto calls internally, so channels are effectively
  // processed one at a time regardless of this concurrency; we keep a small
  // batch so Promise.allSettled still bounds how many are queued at once.
  const CONCURRENCY = 4;
  const deadline = Date.now() + TG_BUDGET_MS;
  const listings = [];
  for (let i = 0; i < channels.length; i += CONCURRENCY) {
    if (Date.now() >= deadline) break;
    const batch = channels.slice(i, i + CONCURRENCY);
    const results = await Promise.allSettled(
      batch.map((ch) => fetchChannelWithRetry(ch, country, filters, deadline)),
    );
    for (const r of results) if (r.status === 'fulfilled') listings.push(...r.value);
  }
  return listings;
}
