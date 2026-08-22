import {
  ensureAvailabilitySchema,
  verifyListingAvailability,
} from './availability.js';

export function installAvailabilityRoutes(app) {
  // Warm the tiny ALTER TABLE migration during startup, but never make backend
  // startup depend on it. The first request retries if PostgreSQL was not ready.
  void ensureAvailabilitySchema().catch((error) => {
    console.warn('[availability] startup schema init failed:', error?.message ?? error);
  });

  app.post('/api/listings/verify', async (req, res) => {
    const items = Array.isArray(req.body?.items) ? req.body.items : [];
    if (!items.length) {
      return res.json({ results: [] });
    }

    try {
      const results = await verifyListingAvailability(items);
      return res.json({ results });
    } catch (error) {
      console.warn('[availability] batch verification failed:', error?.message ?? error);
      return res.status(502).json({
        error: error?.message ?? String(error),
        results: [],
      });
    }
  });
}
