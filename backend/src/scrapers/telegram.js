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

export async function fetchChannel(channel, country, filters = {}) {
  const res = await fetch(`https://t.me/s/${encodeURIComponent(channel)}`, {
    headers: { 'User-Agent': UA_HEADER, 'Accept-Language': 'en,ru' },
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`telegram @${channel} HTTP ${res.status}`);
  const html = await res.text();

  // Each message div carries a data-post="channel/id" attribute, so splitting on
  // it gives one self-contained block per post (photo wrap + text div together).
  const blocks = html.split('data-post="').slice(1);
  const out = [];
  for (let i = 0; i < blocks.length; i++) {
    const raw = blocks[i];
    const dataPost = raw.slice(0, raw.indexOf('"')) || null;

    // Message body: the div with class js-message_text inside this block.
    const textIdx = raw.indexOf('js-message_text');
    if (textIdx < 0) continue;
    const after = raw.slice(textIdx);
    const inner = after.slice(after.indexOf('>') + 1, after.indexOf('</div>'));
    const text = stripHtml(inner);
    if (text.length < 10) continue;

    // keyword filter: only keep messages that look like housing posts
    if (!/(apartament|casa|квартир|дом|будин|кімнат|комнат|m2|м2|\$|€|грн|сум|тенге)/i.test(text))
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
  return out;
}

export async function scrapeTelegram(country, filters) {
  const channels = country.telegramChannels ?? [];
  const results = await Promise.allSettled(
    channels.map((ch) => fetchChannel(ch, country, filters)),
  );
  const listings = [];
  for (const r of results) if (r.status === 'fulfilled') listings.push(...r.value);
  return listings;
}
