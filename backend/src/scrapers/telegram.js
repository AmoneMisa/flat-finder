// Telegram adapter. Public Telegram *channels* expose recent posts via the web
// preview at https://t.me/s/<channel> (no bot token needed). Private groups are
// not publicly readable, so only public channels are supported. We parse each
// message's text and pull price/rooms/area from it.

import { makeListing } from '../normalize.js';
import {
  parsePriceFromText,
  parseRoomsFromText,
  parseAreaFromText,
  guessPropertyType,
} from '../textparse.js';

const UA_HEADER =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

function stripHtml(s) {
  return (s || '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/[ \t]+/g, ' ')
    .trim();
}

// Parse one /s/ preview page into listings. Also returns the smallest post id
// seen, which is used as the `before` cursor to page back to older posts.
function parsePage(html, channel, country, filters) {
  // Each message div carries a data-post="channel/id" attribute, so splitting on
  // it gives one self-contained block per post (photo wrap + text div together).
  const blocks = html.split('data-post="').slice(1);
  const out = [];
  let minId = null;
  for (let i = 0; i < blocks.length; i++) {
    const raw = blocks[i];
    const dataPost = raw.slice(0, raw.indexOf('"')) || null;
    // Track the oldest (smallest) numeric post id for pagination.
    const idNum = Number(dataPost?.split('/')[1]);
    if (Number.isFinite(idNum)) minId = minId === null ? idNum : Math.min(minId, idNum);

    // Message body: the div with class js-message_text inside this block.
    const textIdx = raw.indexOf('js-message_text');
    if (textIdx < 0) continue;
    const after = raw.slice(textIdx);
    const inner = after.slice(after.indexOf('>') + 1, after.indexOf('</div>'));
    const text = stripHtml(inner);
    if (text.length < 10) continue;

    // keyword filter: only keep messages that look like housing posts. Covers
    // RU/UA/RO plus Uzbek (uy/kvartira/xona/ijara) and Kazakh (пәтер/үй/жалға),
    // which the old RU-only list dropped — the main reason UZ/KZ Telegram posts
    // were under-represented.
    if (
      !/(apartament|casa|квартир|kvartira|\bkv\b|дом|\buy|будин|пәтер|үй|кімнат|комнат|xona|ijara|arenda|аренд|жал[гғ]а|m2|м2|кв\.?\s?м|\$|€|грн|сум|so'?m|тенге|у\.?е)/i.test(
        text,
      )
    )
      continue;
    if (filters.query && !text.toLowerCase().includes(filters.query.toLowerCase())) continue;

    const { price, currency } = parsePriceFromText(text, country.currency);
    const type =
      filters.propertyType === 'house' || filters.propertyType === 'flat'
        ? filters.propertyType
        : guessPropertyType(text);
    // Photo is the background-image of tgme_widget_message_photo_wrap (first one).
    const photo =
      raw.match(/tgme_widget_message_photo_wrap[^>]*background-image:\s*url\(['"]?([^'")]+)/i)?.[1] ??
      null;
    const title = text.split('\n')[0].slice(0, 90);
    // Post time: the <time datetime="..."> inside this message block. Lets the
    // caller drop stale posts (we only surface listings < 3 weeks old).
    const createdAt =
      raw.match(/<time[^>]*datetime="([^"]+)"/i)?.[1] ?? null;

    out.push(
      makeListing({
        id: `tg-${channel}-${dataPost ?? i}`,
        source: 'telegram',
        country: country.code,
        title,
        description: text,
        propertyType: type,
        byAgency: false,
        price,
        currency,
        rooms: parseRoomsFromText(text),
        areaSqm: parseAreaFromText(text),
        city: `@${channel}`,
        lat: null,
        lng: null,
        photo,
        url: dataPost ? `https://t.me/${dataPost}` : `https://t.me/s/${channel}`,
        createdAt,
      }),
    );
  }
  return { out, minId };
}

// Fetch a single /s/ page, optionally paging back with a `before` cursor.
async function fetchPage(channel, before) {
  const url = before
    ? `https://t.me/s/${encodeURIComponent(channel)}?before=${before}`
    : `https://t.me/s/${encodeURIComponent(channel)}`;
  const res = await fetch(url, {
    headers: { 'User-Agent': UA_HEADER, 'Accept-Language': 'en,ru' },
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`telegram @${channel} HTTP ${res.status}`);
  return res.text();
}

// A single /s/ page shows only ~20 recent posts, so a busy channel yields very
// few housing hits. Page back a few times via the `?before=<id>` cursor to
// gather more — this is the main lever for telegram listing volume.
const TG_MAX_PAGES = 4;

export async function fetchChannel(channel, country, filters = {}) {
  const listings = [];
  let before = null;
  for (let page = 0; page < TG_MAX_PAGES; page++) {
    const html = await fetchPage(channel, before);
    const { out, minId } = parsePage(html, channel, country, filters);
    listings.push(...out);
    // Stop when a page has no posts at all (end of history / throttled), or when
    // the cursor didn't advance.
    if (minId === null || minId === before) break;
    before = minId;
  }
  return listings;
}

// Fetch a channel with one retry. Telegram's web preview returns a 200 with an
// empty/placeholder page when it throttles a datacenter IP, so an empty result
// is retried once after a short pause as well as outright errors.
async function fetchChannelWithRetry(channel, country, filters) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const r = await fetchChannel(channel, country, filters);
      if (r.length > 0 || attempt === 1) return r;
    } catch (err) {
      if (attempt === 1) return [];
    }
    await new Promise((r) => setTimeout(r, 700));
  }
  return [];
}

export async function scrapeTelegram(country, filters) {
  const channels = country.telegramChannels ?? [];
  // Fetch in small batches instead of all at once: firing 10+ simultaneous
  // requests from one server IP makes Telegram throttle most of them to empty
  // pages, which is why production saw far fewer posts than local dev.
  const CONCURRENCY = 4;
  const listings = [];
  for (let i = 0; i < channels.length; i += CONCURRENCY) {
    const batch = channels.slice(i, i + CONCURRENCY);
    const results = await Promise.allSettled(
      batch.map((ch) => fetchChannelWithRetry(ch, country, filters)),
    );
    for (const r of results) if (r.status === 'fulfilled') listings.push(...r.value);
  }
  return listings;
}
