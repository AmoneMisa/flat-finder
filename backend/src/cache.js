// Process-local fallback cache used only by the legacy/custom-source path.
// Normal Flat Finder requests are served directly from PostgreSQL and never
// read country-wide snapshots from this module.

export function createMemoryCache({
  now = () => Date.now(),
  maxEntries = Number(process.env.LEGACY_CACHE_MAX_ENTRIES) || 500,
} = {}) {
  const mem = new Map(); // key -> { entry, expiresAt }

  function sweepExpired(timestamp) {
    for (const [key, hit] of mem) {
      if (hit.expiresAt != null && timestamp >= hit.expiresAt) {
        mem.delete(key);
      }
    }
  }

  function evictOldest() {
    const oldest = mem.keys().next();
    if (!oldest.done) mem.delete(oldest.value);
  }

  function get(key) {
    const normalizedKey = String(key);
    const hit = mem.get(normalizedKey);
    if (!hit) return null;

    if (hit.expiresAt != null && now() >= hit.expiresAt) {
      mem.delete(normalizedKey);
      return null;
    }

    // Refresh insertion order so frequently used snapshots are evicted last.
    mem.delete(normalizedKey);
    mem.set(normalizedKey, hit);
    return hit.entry;
  }

  function set(key, entry, ttlMs) {
    const timestamp = now();
    const normalizedKey = String(key);
    const ttl = Number(ttlMs);

    mem.delete(normalizedKey);
    sweepExpired(timestamp);

    while (mem.size >= Math.max(1, maxEntries)) {
      evictOldest();
    }

    mem.set(normalizedKey, {
      entry,
      expiresAt: Number.isFinite(ttl) && ttl > 0 ? timestamp + ttl : null,
    });
  }

  return {get, set};
}

const cache = createMemoryCache();

export async function cacheGet(key) {
  return cache.get(key);
}

export async function cacheSet(key, entry, ttlMs) {
  cache.set(key, entry, ttlMs);
}

export function cacheBackend() {
  return 'memory';
}
