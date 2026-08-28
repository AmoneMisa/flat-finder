import {COUNTRIES, COUNTRY_CODES} from './countries.js';
import {
  readFreshActiveListing,
  recordListingAvailability,
} from './availability.js';
import {fetchOlxOffer} from './scrapers/olx.js';
import {validateCustomSource} from './custom-source-queue.js';
import {checkRate} from './request-rate-limit.js';
import {pool} from './db.js';

export function installListingItemRoutes(app) {
  // The listings.id BIGSERIAL is stamped onto every row's data->>'publicId' by
  // the listings_sync_public_id trigger (migration 018), so it is a stable,
  // source-independent way to look an advert back up from a short shared link
  // without needing its source/country/source_id triple.
  app.get('/api/listing/by-public-id/:publicId', async (req, res) => {
    const publicId = Number(req.params.publicId);
    if (!Number.isInteger(publicId) || publicId <= 0) {
      return res.status(400).json({error: 'Invalid public id'});
    }

    try {
      const result = await pool.query(`
        SELECT id, source, country, source_id, data
        FROM listings
        WHERE id = $1 AND active = TRUE
        LIMIT 1
      `, [publicId]);

      const row = result.rows[0];
      if (!row) return res.status(404).json({error: 'Listing not found'});

      return res.json({
        listing: {
          ...(row.data || {}),
          publicId: Number(row.id),
        },
        source: row.source,
        country: row.country,
        sourceId: row.source_id,
      });
    } catch (err) {
      return res.status(502).json({error: err.message});
    }
  });

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
      // A successful source check suppresses every further source request for
      // one hour. Inactive adverts never reach this branch again through the
      // feed: they are persisted inactive and removed from search results.
      const cached = await readFreshActiveListing({source, country: code, id});
      if (cached) {
        return res.json({
          listing: cached.listing,
          availability: {status: 'active', checkedAt: cached.checkedAt, cached: true},
        });
      }

      // fetchOlxOffer is already a live source request. The previous path first
      // called /olx/check and then fetched the offer again, doubling latency and
      // WAF exposure for every click. One source fetch now serves as both the
      // availability check and the fresh listing reload.
      const listing = await fetchOlxOffer(country, id);
      if (!listing) {
        await recordListingAvailability({
          source,
          country: code,
          id,
          status: 'inactive',
          reason: 'offer_not_found',
        });
        return res.status(404).json({error: 'Listing no longer available'});
      }

      const availability = await recordListingAvailability({
        source,
        country: code,
        id,
        status: 'active',
        reason: 'offer_reload',
      });
      return res.json({
        listing: {
          ...listing,
          ...(availability.publicId ? {publicId: availability.publicId} : {}),
        },
        availability: {status: 'active', checkedAt: availability.checkedAt, cached: false},
      });
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
