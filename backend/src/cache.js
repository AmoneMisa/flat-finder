// Cache backend with a shared Redis store and an in-memory fallback.
//
// Redis is OPTIONAL: it is only used when REDIS_URL is set AND the `redis`
// package is installed and reachable. In every other case (no env var, package
// missing, connection error) we silently fall back to a process-local Map so the
// server keeps working exactly as before. This keeps deploys safe — nothing here
// can crash the app if Redis is unavailable.
//
// Values are plain JSON-serializable cache entries ({ at, listings, ... }).

const KEY_PREFIX = 'ff:'; // namespace so we don't collide with other Redis users
const mem = new Map(); // key -> { entry, expiresAt } (fallback store)

let client = null; // resolved redis client, or null when using the fallback
let ready = false;
let initPromise = null;

// Connect to Redis lazily on first use. Never throws: on any failure we log once
// and stick with the in-memory Map for the process lifetime.
async function ensureClient() {
  if (initPromise) return initPromise;
  initPromise = (async () => {
    const url = process.env.REDIS_URL;
    if (!url) return; // Redis disabled — use in-memory fallback.
    try {
      const { createClient } = await import('redis');
      const c = createClient({ url });
      // A single error listener prevents an unhandled 'error' from crashing the
      // process; we downgrade to the fallback and keep serving.
      c.on('error', (err) => {
        if (ready) console.warn('[cache] redis error, using in-memory fallback:', err.message);
        ready = false;
      });
      await c.connect();
      client = c;
      ready = true;
      console.log('[cache] connected to Redis');
    } catch (err) {
      console.warn('[cache] Redis unavailable, using in-memory cache:', err.message);
      client = null;
      ready = false;
    }
  })();
  return initPromise;
}

// Kick off the connection at import so the first request isn't slowed by it.
ensureClient();

function memGet(key) {
  const hit = mem.get(key);
  if (!hit) return null;
  if (hit.expiresAt && Date.now() > hit.expiresAt) {
    mem.delete(key);
    return null;
  }
  return hit.entry;
}

function memSet(key, entry, ttlMs) {
  mem.set(key, { entry, expiresAt: ttlMs ? Date.now() + ttlMs : null });
}

// Read a cache entry. Returns the parsed object or null on miss/error.
export async function cacheGet(key) {
  await ensureClient();
  const k = KEY_PREFIX + key;
  if (client && ready) {
    try {
      const raw = await client.get(k);
      // Mirror into the in-memory store so a later Redis blip still has data.
      if (raw != null) {
        const entry = JSON.parse(raw);
        return entry;
      }
      return null;
    } catch (err) {
      console.warn('[cache] get failed, falling back to memory:', err.message);
    }
  }
  return memGet(k);
}

// Write a cache entry with a TTL (ms). Always writes the in-memory copy too, so
// a Redis outage after a successful set still serves from memory.
export async function cacheSet(key, entry, ttlMs) {
  await ensureClient();
  const k = KEY_PREFIX + key;
  memSet(k, entry, ttlMs);
  if (client && ready) {
    try {
      await client.set(k, JSON.stringify(entry), { PX: Math.max(1, ttlMs | 0) });
    } catch (err) {
      console.warn('[cache] set failed (kept in memory):', err.message);
    }
  }
}

// Whether a shared Redis backend is currently active (for diagnostics).
export function cacheBackend() {
  return client && ready ? 'redis' : 'memory';
}
