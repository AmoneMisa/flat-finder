// Reddit adapter. Uses Reddit's public JSON API (no auth needed for read-only,
// just a descriptive User-Agent). Searches each configured subreddit for the
// property type / keyword and parses price/rooms/area from the post text.

import { makeListing } from '../normalize.js';
import {
  parsePriceFromText,
  parseRoomsFromText,
  parseAreaFromText,
  guessPropertyType,
} from '../textparse.js';

// Reddit requires a descriptive User-Agent (ideally "<platform>:<appid>:<ver>
// (by /u/<username>)"). Override via REDDIT_USER_AGENT.
const UA_HEADER =
  process.env.REDDIT_USER_AGENT || 'nodejs:flat-finder:1.0 (by /u/flatfinderbot)';

// Reddit now requires OAuth for its API — the anonymous .json endpoints return
// HTTP 403 from server / datacenter IPs no matter the User-Agent. So we ONLY
// work when app credentials are supplied via env:
//   REDDIT_CLIENT_ID / REDDIT_CLIENT_SECRET  (create at reddit.com/prefs/apps,
//   type "script" or "web app"). Without them this source is skipped.
let tokenCache = { token: null, exp: 0 };
let warnedNoCreds = false;

async function getToken() {
  const id = process.env.REDDIT_CLIENT_ID;
  const secret = process.env.REDDIT_CLIENT_SECRET;
  if (!id || !secret) return null;
  if (tokenCache.token && Date.now() < tokenCache.exp) return tokenCache.token;

  const res = await fetch('https://www.reddit.com/api/v1/access_token', {
    method: 'POST',
    headers: {
      Authorization: 'Basic ' + Buffer.from(`${id}:${secret}`).toString('base64'),
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': UA_HEADER,
    },
    body: 'grant_type=client_credentials',
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`reddit token HTTP ${res.status}`);
  const j = await res.json();
  tokenCache = { token: j.access_token, exp: Date.now() + (j.expires_in - 60) * 1000 };
  return tokenCache.token;
}

function buildQuery(country, filters) {
  const terms = [];
  if (filters.propertyType === 'flat') terms.push('apartment');
  else if (filters.propertyType === 'house') terms.push('house');
  else terms.push('apartment OR house OR rent OR sale');
  const dealWords = {
    sale: 'sale OR buy',
    longRent: 'rent OR rental',
    shortRent: 'short term OR daily OR nightly',
  };
  if (dealWords[filters.dealType]) terms.push(`(${dealWords[filters.dealType]})`);
  if (filters.query) terms.push(filters.query);
  return terms.join(' ');
}

async function searchSub(sub, q, country, filters, token) {
  const url =
    `https://oauth.reddit.com/r/${encodeURIComponent(sub)}/search.json` +
    `?q=${encodeURIComponent(q)}&restrict_sr=1&sort=new&limit=25&raw_json=1`;
  const headers = {
    'User-Agent': UA_HEADER,
    Accept: 'application/json',
    Authorization: `Bearer ${token}`,
  };
  let res = await fetch(url, { headers, signal: AbortSignal.timeout(10_000) });

  // One retry: token may have just expired (401) or we hit a rate limit (429).
  if (res.status === 401) {
    tokenCache = { token: null, exp: 0 };
    const fresh = await getToken();
    if (fresh) {
      headers.Authorization = `Bearer ${fresh}`;
      res = await fetch(url, { headers, signal: AbortSignal.timeout(10_000) });
    }
  } else if (res.status === 429) {
    const wait = Math.min(3000, (Number(res.headers.get('retry-after')) || 2) * 1000);
    await new Promise((r) => setTimeout(r, wait));
    res = await fetch(url, { headers, signal: AbortSignal.timeout(10_000) });
  }

  if (!res.ok) throw new Error(`reddit r/${sub} HTTP ${res.status}`);
  const json = await res.json();
  const children = json?.data?.children ?? [];

  return children
    .map((c) => c.data)
    .filter((p) => p && !p.stickied)
    .map((p) => {
      const text = `${p.title}\n${p.selftext || ''}`;
      const { price, currency } = parsePriceFromText(text, country.currency);
      const type =
        filters.propertyType === 'house' || filters.propertyType === 'flat'
          ? filters.propertyType
          : guessPropertyType(text);
      const photo =
        p.preview?.images?.[0]?.source?.url?.replace(/&amp;/g, '&') ||
        (p.thumbnail && p.thumbnail.startsWith('http') ? p.thumbnail : null);

      return makeListing({
        id: `reddit-${p.id}`,
        source: 'reddit',
        country: country.code,
        title: p.title,
        description: p.selftext || '',
        propertyType: type,
        byAgency: false, // Reddit posts are overwhelmingly private individuals
        price,
        currency,
        rooms: parseRoomsFromText(text),
        areaSqm: parseAreaFromText(text),
        city: `r/${p.subreddit}`,
        lat: null,
        lng: null, // no geodata on Reddit posts -> list only, no map pin
        photo,
        url: `https://www.reddit.com${p.permalink}`,
        createdAt: p.created_utc ? new Date(p.created_utc * 1000).toISOString() : null,
      });
    });
}

export async function scrapeReddit(country, filters) {
  const token = await getToken().catch((e) => {
    console.warn(`[reddit] token fetch failed: ${e.message}`);
    return null;
  });

  // No credentials -> the anonymous API is 403 from servers, so there is nothing
  // useful to fetch. Warn once and skip instead of hammering a blocked endpoint.
  if (!token) {
    if (!warnedNoCreds) {
      warnedNoCreds = true;
      console.warn(
        '[reddit] no REDDIT_CLIENT_ID/REDDIT_CLIENT_SECRET set — Reddit source ' +
          'disabled (anonymous API returns 403). Create an app at ' +
          'https://www.reddit.com/prefs/apps and set the env vars.',
      );
    }
    return [];
  }

  const q = buildQuery(country, filters);
  const subs = country.subreddits ?? [];
  const results = await Promise.allSettled(
    subs.map((s) => searchSub(s, q, country, filters, token)),
  );
  const listings = [];
  for (const r of results) if (r.status === 'fulfilled') listings.push(...r.value);
  return listings;
}
