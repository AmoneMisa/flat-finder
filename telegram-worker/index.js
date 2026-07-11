// Telegram MTProto sidecar (GramJS).
//
// The backend used to scrape https://t.me/s/<channel>, but Telegram heavily
// throttles that web preview from datacenter IPs (a production server saw ~1
// post where a residential browser sees hundreds). This worker instead logs in
// once as a real user account (session string in TG_SESSION) and calls the
// MTProto API directly, which is not throttled the same way and returns
// structured messages — no HTML parsing.
//
// It is transport-only: it hands raw message text/date back to the backend,
// which keeps all the housing parsing/filtering logic in one place.

import express from 'express';
import { TelegramClient } from 'telegram';
import { StringSession } from 'telegram/sessions/index.js';

const apiId = Number(process.env.TG_API_ID);
const apiHash = process.env.TG_API_HASH;
const session = process.env.TG_SESSION || '';
const port = Number(process.env.PORT) || 4100;

if (!apiId || !apiHash || !session) {
  console.error(
    '[tg-worker] TG_API_ID, TG_API_HASH and TG_SESSION are required. ' +
      'Generate a session with `npm run login`.',
  );
  process.exit(1);
}

const client = new TelegramClient(new StringSession(session), apiId, apiHash, {
  connectionRetries: 5,
  // Auto-wait through short FLOOD_WAITs (Telegram asking us to slow down)
  // instead of erroring; anything longer than this surfaces as an error.
  floodSleepThreshold: 60,
});

// Resolving a @username to an entity is itself an API call, so cache the
// resolved entity per channel for the process lifetime.
const entityCache = new Map();
async function resolve(channel) {
  if (entityCache.has(channel)) return entityCache.get(channel);
  const entity = await client.getEntity(channel);
  entityCache.set(channel, entity);
  return entity;
}

// Serialize all history calls through a single-lane queue. Firing many MTProto
// requests in parallel from one account is the fastest way to trip FLOOD_WAIT
// or an account limit, so we trade a little latency for safety.
let chain = Promise.resolve();
function enqueue(task) {
  const run = chain.then(task, task);
  // Keep the chain alive regardless of individual task outcome.
  chain = run.then(
    () => undefined,
    () => undefined,
  );
  return run;
}

// Small in-memory LRU for downloaded photo bytes, so repeated views of the same
// listing (or several users) don't each re-download from Telegram — every
// download is a rate-limited API call. The real long-term cache is client-side
// (the app's cached_network_image + the HTTP cache headers the backend sets);
// this just absorbs bursts. Capped by entry count to bound memory.
const PHOTO_CACHE_MAX = 300;
const photoCache = new Map(); // "channel/id" -> Buffer
function cacheGetPhoto(key) {
  const buf = photoCache.get(key);
  if (buf) {
    // Refresh recency (Map preserves insertion order).
    photoCache.delete(key);
    photoCache.set(key, buf);
  }
  return buf;
}
function cacheSetPhoto(key, buf) {
  photoCache.set(key, buf);
  while (photoCache.size > PHOTO_CACHE_MAX) {
    photoCache.delete(photoCache.keys().next().value);
  }
}

const app = express();

app.get('/health', (_req, res) => {
  res.json({ ok: client.connected === true });
});

// GET /photo?channel=<name>&id=<messageId>
// Downloads the photo attached to one message and returns the raw JPEG bytes.
// Lazy (only when a client actually views the listing) and cached, since media
// downloads are themselves rate-limited MTProto calls.
app.get('/photo', async (req, res) => {
  const channel = String(req.query.channel || '').trim();
  const id = Number(req.query.id);
  if (!channel || !Number.isFinite(id)) {
    return res.status(400).json({ ok: false, error: 'channel and numeric id required' });
  }
  const key = `${channel}/${id}`;

  try {
    let buf = cacheGetPhoto(key);
    if (!buf) {
      buf = await enqueue(async () => {
        const entity = await resolve(channel);
        const [msg] = await client.getMessages(entity, { ids: [id] });
        if (!msg || !msg.photo) return null;
        return client.downloadMedia(msg, {});
      });
      if (!buf) return res.status(404).json({ ok: false, error: 'no photo' });
      cacheSetPhoto(key, buf);
    }
    res.setHeader('Content-Type', 'image/jpeg');
    res.send(buf);
  } catch (err) {
    const msg = err?.message ?? String(err);
    console.warn(`[tg-worker] photo ${key} failed: ${msg}`);
    res.status(502).json({ ok: false, error: msg });
  }
});

// GET /history?channel=<name>&limit=<n>&beforeId=<id>
//   channel  : public channel username (without @)
//   limit    : max messages to return (default 100)
//   beforeId : paginate to messages older than this id (the `offsetId` cursor)
//
// Returns { ok, messages: [{ id, text, date, hasPhoto }], minId }.
app.get('/history', async (req, res) => {
  const channel = String(req.query.channel || '').trim();
  if (!channel) return res.status(400).json({ ok: false, error: 'channel required' });
  const limit = Math.min(Number(req.query.limit) || 100, 200);
  const beforeId = Number(req.query.beforeId) || 0;

  try {
    const messages = await enqueue(async () => {
      const entity = await resolve(channel);
      return client.getMessages(entity, { limit, offsetId: beforeId });
    });

    const out = [];
    let minId = null;
    for (const m of messages) {
      if (typeof m.id === 'number') {
        minId = minId === null ? m.id : Math.min(minId, m.id);
      }
      const text = m.message || '';
      if (!text) continue; // service messages, pure media with no caption, etc.
      out.push({
        id: m.id,
        text,
        // GramJS exposes the unix timestamp (seconds) as `date`.
        date: m.date ? new Date(m.date * 1000).toISOString() : null,
        hasPhoto: Boolean(m.photo),
      });
    }
    res.json({ ok: true, messages: out, minId });
  } catch (err) {
    const msg = err?.message ?? String(err);
    console.warn(`[tg-worker] @${channel} failed: ${msg}`);
    res.status(502).json({ ok: false, error: msg });
  }
});

await client.connect();
console.log('[tg-worker] connected to Telegram');
app.listen(port, () => console.log(`[tg-worker] listening on :${port}`));
