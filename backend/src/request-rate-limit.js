// Process-local flood protection for explicit manual reload actions.
// Normal read-only search requests are never rate-limited here.
const buckets = new Map();

export function checkRate(req, res, bucket, windowMs) {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const key = `${bucket}:${ip}`;
  const now = Date.now();
  const wait = (buckets.get(key) || 0) + windowMs - now;

  if (wait > 0) {
    res.set('Retry-After', String(Math.ceil(wait / 1000)));
    res.status(429).json({
      error: 'Too many reload requests',
      retryAfterMs: wait,
    });
    return false;
  }

  buckets.set(key, now);
  return true;
}
