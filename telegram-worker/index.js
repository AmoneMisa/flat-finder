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

const app = express();

app.get('/health', (_req, res) => {
  res.json({ ok: client.connected === true });
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
