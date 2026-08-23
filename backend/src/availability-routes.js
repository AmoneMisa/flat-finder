import { ensureAvailabilitySchema } from './availability.js';
import { readListingAvailability } from './availability-sweep.js';

export function installAvailabilityRoutes(app) {
  // Warm the tiny ALTER TABLE migration during startup, but never make backend
  // startup depend on it. The first request retries if PostgreSQL was not ready.
  void ensureAvailabilitySchema().catch((error) => {
    console.warn('[availability] startup schema init failed:', error?.message ?? error);
  });

  // Compatibility endpoint for existing clients. It now only reads persisted
  // availability state; source checks are performed by the isolated worker.
  app.post('/api/listings/verify', async (req, res) => {
    const items = Array.isArray(req.body?.items) ? req.body.items : [];
    if (!items.length) {
      return res.json({ results: [] });
    }

    try {
      const results = await readListingAvailability(items);
      return res.json({ results, verificationOwner: 'worker' });
    } catch (error) {
      console.warn('[availability] state read failed:', error?.message ?? error);
      return res.status(500).json({
        error: error?.message ?? String(error),
        results: [],
      });
    }
  });
}
