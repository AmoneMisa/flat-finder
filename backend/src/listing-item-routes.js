import {COUNTRIES, COUNTRY_CODES} from './countries.js';
import {fetchOlxOffer} from './scrapers/olx.js';
import {validateCustomSource} from './custom-source-queue.js';
import {checkRate} from './request-rate-limit.js';

export function installListingItemRoutes(app) {
  app.get('/api/listing/:source/:id', async (req, res) => {
    if (!checkRate(req, res, 'reloadOne', 1500)) return;

    const source = String(req.params.source).toLowerCase();
    const id = String(req.params.id);
    const code = String(req.query.country || '').toUpperCase();
    const country = COUNTRIES[code];

    if (!country) return res.status(400).json({error: 'Unknown country'});
    if (source !== 'olx') {
      return res.status(400).json({
        error: 'Reload not supported for this source',
      });
    }

    try {
      const listing = await fetchOlxOffer(country, id);
      if (!listing) {
        return res.status(404).json({error: 'Listing no longer available'});
      }
      return res.json({listing});
    } catch (err) {
      return res.status(502).json({error: err.message});
    }
  });

  app.post('/api/sources/validate', async (req, res) => {
    if (!checkRate(req, res, 'customSourceValidate', 3000)) return;

    const url = String(req.body?.url || '').trim();
    if (!url) return res.status(400).json({ok: false, error: 'Missing url'});

    const code = String(req.body?.country || 'RO').toUpperCase();
    const country = COUNTRIES[code] ?? COUNTRIES[COUNTRY_CODES[0]];
    const result = await validateCustomSource(url, country.code);
    return res.json(result);
  });
}