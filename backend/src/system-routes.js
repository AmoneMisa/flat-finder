import { dbHealth, getDbStats } from './db.js';
import { elasticsearchHealth } from './elasticsearch.js';
import { requireInternal } from './internal-auth.js';
import { getLastRun, refreshAll } from './scheduler.js';

function requireOps(req, res) {
  return requireInternal(req, res, {
    envNames: ['OPS_INTERNAL_KEY'],
    missingMessage: 'OPS_INTERNAL_KEY/QUEUE_INTERNAL_KEY is not configured',
  });
}

export function installSystemRoutes(app) {
  if (app.locals.systemRoutesInstalled) return;
  app.locals.systemRoutesInstalled = true;

  app.get('/health', async (_req, res) => {
    let postgres = false;
    let elasticsearch = false;
    let elasticsearchStatus = null;

    try {
      await dbHealth();
      postgres = true;
    } catch {}

    try {
      const health = await elasticsearchHealth();
      elasticsearch = health.ok === true;
      elasticsearchStatus = health.status ?? null;
    } catch {}

    // PostgreSQL is the primary listing/search store. Elasticsearch remains
    // an optional text-ranking layer and is not required for backend health.
    const ok = postgres;

    res.status(ok ? 200 : 503).json({
      ok,
      postgres,
      elasticsearch,
      elasticsearchStatus,
    });
  });

  app.get('/internal/db-stats', async (req, res) => {
    if (!requireOps(req, res)) return;

    try {
      const rows = await getDbStats();
      res.json({ ok: true, rows });
    } catch (err) {
      res.status(500).json({
        ok: false,
        error: err?.message ?? String(err),
      });
    }
  });

  app.get('/internal/refresh', (req, res) => {
    if (!requireOps(req, res)) return;
    res.json({ lastRun: getLastRun() });
  });

  app.post('/internal/refresh', async (req, res) => {
    if (!requireOps(req, res)) return;

    try {
      const result = await refreshAll('manual');
      res.json({ ok: true, result });
    } catch (err) {
      res.status(500).json({
        ok: false,
        error: err?.message ?? String(err),
      });
    }
  });
}
