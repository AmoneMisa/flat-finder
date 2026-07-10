// Threads (Meta) adapter — BEST EFFORT.
//
// Threads has no official public read/search API, and its web app renders posts
// client-side behind GraphQL + auth, so a plain server-side fetch generally
// returns an empty JS shell. We attempt to pull any inline JSON that Threads
// occasionally ships for public tag pages; if nothing usable is found we return
// [] (the country still gets results from OLX/Reddit/Telegram, or falls back to
// demo data). To make this source real you would plug in the official
// Threads/Instagram Graph API here.

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

const HOUSING_RE = /(apartament|casa|квартир|дом|будин|xona|kvartira|uy|m2|м2|\$|€|грн|сум|so'?m|тенге|tenge)/i;

let warnedNoApi = false;

// Official path: read posts from a Threads account you own via the Graph API.
// Set THREADS_ACCESS_TOKEN (from developers.facebook.com, Threads API). This is
// the only supported way to read Threads content — there is no public hashtag
// search API — so it works best when the token belongs to an account that posts
// listings (e.g. an agency's own Threads feed).
async function fetchViaApi(country, filters) {
  const token = process.env.THREADS_ACCESS_TOKEN;
  if (!token) return null; // signal "not configured" so caller can fall back

  const url =
    'https://graph.threads.net/v1.0/me/threads' +
    '?fields=id,text,permalink,timestamp&limit=50' +
    `&access_token=${encodeURIComponent(token)}`;
  const res = await fetch(url, {
    headers: { Accept: 'application/json' },
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`threads API HTTP ${res.status}`);
  const json = await res.json();
  const posts = Array.isArray(json?.data) ? json.data : [];

  const out = [];
  for (const p of posts) {
    const text = (p.text || '').trim();
    if (text.length < 10 || !HOUSING_RE.test(text)) continue;
    if (filters.query && !text.toLowerCase().includes(filters.query.toLowerCase())) continue;
    const { price, currency } = parsePriceFromText(text, country.currency);
    const type =
      filters.propertyType === 'house' || filters.propertyType === 'flat'
        ? filters.propertyType
        : guessPropertyType(text);
    out.push(
      makeListing({
        id: `threads-${p.id}`,
        source: 'threads',
        country: country.code,
        title: text.split('\n')[0].slice(0, 90),
        description: text,
        propertyType: type,
        byAgency: false,
        price,
        currency,
        rooms: parseRoomsFromText(text),
        areaSqm: parseAreaFromText(text),
        city: '',
        lat: null,
        lng: null,
        photo: null,
        url: p.permalink || 'https://www.threads.net',
        createdAt: p.timestamp ?? null,
      }),
    );
  }
  return out;
}

export async function fetchTag(tag, country, filters = {}) {
  const res = await fetch(
    `https://www.threads.net/search?q=${encodeURIComponent(tag)}&serp_type=tags`,
    {
      headers: { 'User-Agent': UA_HEADER, 'Accept-Language': 'en' },
      signal: AbortSignal.timeout(6_000),
    },
  );
  if (!res.ok) throw new Error(`threads #${tag} HTTP ${res.status}`);
  const html = await res.text();

  // Threads embeds some data in <script type="application/json"> blobs. Try to
  // find post captions ("text": "...") that look like housing posts.
  // Threads ships captions under a few different JSON keys depending on the
  // surface; try the common ones. (Logged-out search usually yields nothing.)
  const captions = [
    ...html.matchAll(/"(?:text|caption|body_text)":"((?:[^"\\]|\\.){20,}?)"/g),
  ]
    .map((m) => {
      try {
        return JSON.parse(`"${m[1]}"`);
      } catch {
        return '';
      }
    })
    .filter((t) => HOUSING_RE.test(t));

  const seen = new Set();
  const out = [];
  captions.forEach((text, i) => {
    if (seen.has(text)) return;
    seen.add(text);
    if (filters.query && !text.toLowerCase().includes(filters.query.toLowerCase())) return;
    const { price, currency } = parsePriceFromText(text, country.currency);
    const type =
      filters.propertyType === 'house' || filters.propertyType === 'flat'
        ? filters.propertyType
        : guessPropertyType(text);
    out.push(
      makeListing({
        id: `threads-${tag}-${i}`,
        source: 'threads',
        country: country.code,
        title: text.split('\n')[0].slice(0, 90),
        description: text,
        propertyType: type,
        byAgency: false,
        price,
        currency,
        rooms: parseRoomsFromText(text),
        areaSqm: parseAreaFromText(text),
        city: `#${tag}`,
        lat: null,
        lng: null,
        photo: null,
        url: `https://www.threads.net/search?q=${encodeURIComponent(tag)}`,
        createdAt: null,
      }),
    );
  });
  return out;
}

export async function scrapeThreads(country, filters) {
  // Prefer the official Graph API when a token is configured.
  const viaApi = await fetchViaApi(country, filters).catch((e) => {
    console.warn(`[threads] API error: ${e.message}`);
    return [];
  });
  if (viaApi !== null) return viaApi;

  // No token: best-effort HTML scrape (usually empty for logged-out search).
  const tags = country.threadsTags ?? [];
  const results = await Promise.allSettled(tags.map((t) => fetchTag(t, country, filters)));
  const listings = [];
  for (const r of results) if (r.status === 'fulfilled') listings.push(...r.value);

  if (!listings.length && !warnedNoApi) {
    warnedNoApi = true;
    console.warn(
      '[threads] no public listings found and THREADS_ACCESS_TOKEN not set. ' +
        'Threads has no public hashtag-search API; set a Graph API token to read ' +
        'an owned account feed, otherwise this source stays empty.',
    );
  }
  return listings;
}
