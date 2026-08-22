// Process-local fallback cache used only by the legacy/custom-source path.
// Normal Flat Finder requests are served directly from PostgreSQL and never
// read country-wide snapshots from this module.

const mem = new Map(); // key -> { entry, expiresAt }

function getEntry(key) {
  const hit = mem.get(key);
  if (!hit) return null;
  if (hit.expiresAt != null && Date.now() >= hit.expiresAt) {
    mem.delete(key);
    return null;
  }
  return hit.entry;
}

export async function cacheGet(key) {
  return getEntry(String(key));
}

export async function cacheSet(key, entry, ttlMs) {
  const ttl = Number(ttlMs);
  mem.set(String(key), {
    entry,
    expiresAt: Number.isFinite(ttl) && ttl > 0 ? Date.now() + ttl : null,
  });
}

export function cacheBackend() {
  return 'memory';
}
