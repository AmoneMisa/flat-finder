const SOCIAL_FETCHER_URL = String(process.env.SOCIAL_FETCHER_URL || '').replace(/\/$/, '');

function internalKey() {
  return String(process.env.SOCIAL_INTERNAL_KEY || process.env.QUEUE_INTERNAL_KEY || '');
}

function requireInternal(req, res) {
  const expected = internalKey();
  if (expected.length < 16) {
    res.status(503).json({ error: 'SOCIAL_INTERNAL_KEY/QUEUE_INTERNAL_KEY is not configured' });
    return false;
  }
  if (String(req.get('x-queue-key') || '') !== expected) {
    res.status(401).json({ error: 'Unauthorized' });
    return false;
  }
  return true;
}

async function socialRequest(path, options = {}) {
  if (!SOCIAL_FETCHER_URL) {
    throw new Error('SOCIAL_FETCHER_URL is not configured');
  }

  const response = await fetch(`${SOCIAL_FETCHER_URL}${path}`, {
    ...options,
    signal: AbortSignal.timeout(180_000),
  });

  let body;
  try {
    body = await response.json();
  } catch {
    body = { ok: false, error: `Social fetcher returned HTTP ${response.status}` };
  }

  return { response, body };
}

export function installSocialRoutes(app) {
  if (app.locals.socialRoutesInstalled) return;
  app.locals.socialRoutesInstalled = true;

  app.get('/internal/social/health', async (req, res) => {
    if (!requireInternal(req, res)) return;

    try {
      const { response, body } = await socialRequest('/health');
      return res.status(response.status).json(body);
    } catch (error) {
      return res.status(503).json({ ok: false, error: error?.message || String(error) });
    }
  });

  app.post('/internal/social/fetch', async (req, res) => {
    if (!requireInternal(req, res)) return;

    const source = String(req.body?.source || '').toLowerCase();
    if (!['facebook', 'threads', 'linkedin'].includes(source)) {
      return res.status(400).json({
        ok: false,
        error: 'source must be facebook, threads or linkedin',
      });
    }

    try {
      const { response, body } = await socialRequest('/fetch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...req.body, source }),
      });
      return res.status(response.status).json(body);
    } catch (error) {
      return res.status(502).json({ ok: false, error: error?.message || String(error) });
    }
  });
}
