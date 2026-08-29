import {canonicalCity} from '@whiteslove/parsing-lexicon/geography';
import {COUNTRY_CODES} from './countries.js';
import {pool} from './db.js';
import {getRates} from './fx.js';
import {parseListingFilters} from './listing-routes.js';
import {mobilePushConfigured, sendMobilePush} from './mobile-fcm.js';
import {searchPostgresListings} from './postgres-search-fast.js';
import {checkRate} from './request-rate-limit.js';

const SCHEMA = 'subscriptions';
const MAX_PRESETS_PER_DEVICE = 40;
const MAX_NOTIFICATIONS_PER_SCAN = Math.max(
  1,
  Math.min(Number(process.env.MOBILE_SUBSCRIPTION_MAX_NOTIFICATIONS_PER_SCAN) || 8, 30),
);
const POLL_MS = Math.max(
  30_000,
  Math.min(Number(process.env.MOBILE_SUBSCRIPTION_POLL_SECONDS) || 60, 3600) * 1000,
);

let scanTimer;
let scanning = false;

function cleanId(value, max = 80) {
  const result = String(value || '').trim();
  if (result.length < 8 || result.length > max || !/^[A-Za-z0-9._:-]+$/.test(result)) return null;
  return result;
}

function cleanLanguage(value) {
  const lang = String(value || 'ru').trim().toLowerCase();
  return /^[a-z]{2}(?:-[a-z]{2})?$/.test(lang) ? lang.slice(0, 8) : 'ru';
}

function cleanPlatform(value) {
  const platform = String(value || 'android').trim().toLowerCase();
  return ['android', 'ios'].includes(platform) ? platform : 'android';
}

function normalizePreset(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const id = cleanId(raw.id);
  if (!id) return null;
  const name = String(raw.name || 'Preset').trim().slice(0, 120) || 'Preset';
  const filters = raw.filters && typeof raw.filters === 'object' && !Array.isArray(raw.filters)
    ? raw.filters
    : {};
  return {id, name, filters};
}

function snapshotQuery(snapshot) {
  const query = {};
  for (const [key, value] of Object.entries(snapshot || {})) {
    if (value == null || value === '') continue;
    if (key === 'countries' || key === 'amenities' || key === 'sort') continue;
    if (key === 'sources' || key === 'customSources') {
      query[key] = Array.isArray(value) ? value.join(',') : String(value);
      continue;
    }
    query[key] = typeof value === 'boolean' ? (value ? 'true' : '') : value;
  }
  for (const amenity of Array.isArray(snapshot?.amenities) ? snapshot.amenities : []) {
    const key = String(amenity || '').trim();
    if (key) query[key] = 'true';
  }
  query.sort = 'newest';
  query.limit = '60';
  query.offset = '0';
  return query;
}

export function mobilePresetSearch(snapshot) {
  const requestedCountries = Array.isArray(snapshot?.countries)
    ? snapshot.countries
    : String(snapshot?.countries || '').split(',');
  const countries = [...new Set(requestedCountries
    .map((value) => String(value).trim().toUpperCase())
    .filter((value) => COUNTRY_CODES.includes(value)))];
  const codes = countries.length ? countries : COUNTRY_CODES;
  const filters = parseListingFilters(snapshotQuery(snapshot));
  if (filters.city) {
    const country = codes.length === 1 ? codes[0] : undefined;
    filters.city = canonicalCity(filters.city, country) || filters.city;
  }
  return {filters, countries: codes};
}

async function syncDevice({deviceId, pushToken, platform, language, enabled, presets}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`
      INSERT INTO ${SCHEMA}.mobile_devices
        (device_id, push_token, platform, language, enabled)
      VALUES ($1, $2, $3, $4, $5)
      ON CONFLICT (device_id) DO UPDATE SET
        push_token = EXCLUDED.push_token,
        platform = EXCLUDED.platform,
        language = EXCLUDED.language,
        enabled = EXCLUDED.enabled,
        updated_at = NOW();
    `, [deviceId, pushToken, platform, language, enabled]);

    const presetIds = [];
    for (const preset of presets) {
      presetIds.push(preset.id);
      const result = await client.query(`
        INSERT INTO ${SCHEMA}.mobile_subscriptions
          (device_id, preset_id, name, filters, enabled)
        VALUES ($1, $2, $3, $4::jsonb, TRUE)
        ON CONFLICT (device_id, preset_id) DO UPDATE SET
          name = EXCLUDED.name,
          filters = EXCLUDED.filters,
          enabled = TRUE,
          initialized = CASE
            WHEN ${SCHEMA}.mobile_subscriptions.filters IS DISTINCT FROM EXCLUDED.filters
              OR ${SCHEMA}.mobile_subscriptions.enabled = FALSE
              THEN FALSE
            ELSE ${SCHEMA}.mobile_subscriptions.initialized
          END,
          last_checked_at = CASE
            WHEN ${SCHEMA}.mobile_subscriptions.filters IS DISTINCT FROM EXCLUDED.filters
              OR ${SCHEMA}.mobile_subscriptions.enabled = FALSE
              THEN NULL
            ELSE ${SCHEMA}.mobile_subscriptions.last_checked_at
          END,
          updated_at = NOW()
        RETURNING id, initialized;
      `, [deviceId, preset.id, preset.name, JSON.stringify(preset.filters)]);
      const row = result.rows[0];
      if (row && !row.initialized) {
        await client.query(
          `DELETE FROM ${SCHEMA}.mobile_subscription_seen WHERE subscription_id = $1`,
          [row.id],
        );
      }
    }

    if (presetIds.length) {
      await client.query(`
        DELETE FROM ${SCHEMA}.mobile_subscriptions
        WHERE device_id = $1 AND NOT (preset_id = ANY($2::text[]));
      `, [deviceId, presetIds]);
    } else {
      await client.query(`DELETE FROM ${SCHEMA}.mobile_subscriptions WHERE device_id = $1`, [deviceId]);
    }

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export function registerMobileSubscriptionRoutes(app) {
  app.get('/api/mobile-subscriptions/config', (_req, res) => {
    res.json({pushTransportConfigured: mobilePushConfigured()});
  });

  app.put('/api/mobile-subscriptions', async (req, res) => {
    if (!checkRate(req, res, 'mobile-subscriptions', 750)) return;
    const deviceId = cleanId(req.body?.deviceId);
    if (!deviceId) return res.status(400).json({error: 'Invalid deviceId'});
    const pushToken = String(req.body?.pushToken || '').trim().slice(0, 4096);
    const enabled = req.body?.enabled !== false;
    const platform = cleanPlatform(req.body?.platform);
    const language = cleanLanguage(req.body?.language);
    const rawPresets = Array.isArray(req.body?.presets) ? req.body.presets : [];
    if (rawPresets.length > MAX_PRESETS_PER_DEVICE) {
      return res.status(400).json({error: `At most ${MAX_PRESETS_PER_DEVICE} presets are allowed`});
    }
    const presets = rawPresets.map(normalizePreset).filter(Boolean);
    if (presets.length !== rawPresets.length) {
      return res.status(400).json({error: 'Invalid preset payload'});
    }
    try {
      await syncDevice({deviceId, pushToken, platform, language, enabled, presets});
      return res.json({ok: true, count: presets.length, pushTransportConfigured: mobilePushConfigured()});
    } catch (err) {
      console.error('[mobile-subscriptions] sync failed:', err);
      return res.status(500).json({error: 'Could not save mobile subscriptions'});
    }
  });
}

async function enabledSubscriptions() {
  const result = await pool.query(`
    SELECT s.*, d.push_token, d.language, d.platform
    FROM ${SCHEMA}.mobile_subscriptions s
    JOIN ${SCHEMA}.mobile_devices d ON d.device_id = s.device_id
    WHERE s.enabled = TRUE AND d.enabled = TRUE AND d.push_token <> ''
    ORDER BY s.id ASC;
  `);
  return result.rows;
}

async function primeSeen(subscription, items) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const item of items) {
      const key = listingKey(item);
      if (!key) continue;
      await client.query(`
        INSERT INTO ${SCHEMA}.mobile_subscription_seen (subscription_id, item_key)
        VALUES ($1, $2)
        ON CONFLICT DO NOTHING;
      `, [subscription.id, key]);
    }
    await client.query(`
      UPDATE ${SCHEMA}.mobile_subscriptions
      SET initialized = TRUE, last_checked_at = NOW()
      WHERE id = $1;
    `, [subscription.id]);
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

function listingKey(item) {
  const source = String(item?.source || '').toLowerCase();
  const country = String(item?.country || '').toUpperCase();
  const id = String(item?.id || item?.url || '').trim();
  return source && id ? `${source}:${country}:${id}` : null;
}

async function fetchMatches(subscription) {
  const {filters, countries} = mobilePresetSearch(subscription.filters || {});
  let rates = null;
  try {
    rates = (await getRates()).rates;
  } catch {}
  const result = await searchPostgresListings({filters, countries, rates, searchMatches: null});
  return result.listings || [];
}

async function seen(subscriptionId, key) {
  const result = await pool.query(`
    SELECT 1 FROM ${SCHEMA}.mobile_subscription_seen
    WHERE subscription_id = $1 AND item_key = $2;
  `, [subscriptionId, key]);
  return result.rowCount > 0;
}

async function delivered(deviceId, key) {
  const result = await pool.query(`
    SELECT 1 FROM ${SCHEMA}.mobile_deliveries
    WHERE device_id = $1 AND kind = 'flats' AND item_key = $2;
  `, [deviceId, key]);
  return result.rowCount > 0;
}

async function markSeen(subscriptionId, key) {
  await pool.query(`
    INSERT INTO ${SCHEMA}.mobile_subscription_seen (subscription_id, item_key)
    VALUES ($1, $2) ON CONFLICT DO NOTHING;
  `, [subscriptionId, key]);
}

async function markDelivered(subscription, key) {
  await pool.query(`
    INSERT INTO ${SCHEMA}.mobile_deliveries
      (device_id, kind, item_key, first_subscription_id)
    VALUES ($1, 'flats', $2, $3) ON CONFLICT DO NOTHING;
  `, [subscription.device_id, key, subscription.id]);
}

function notificationText(subscription, item) {
  const price = item?.price != null
    ? `${Math.round(Number(item.price)).toLocaleString('en-US')} ${item.currency || ''}`.trim()
    : null;
  const location = [item?.city, item?.district].filter(Boolean).join(', ');
  const title = String(subscription.language || '').startsWith('ru')
    ? `Новое жильё · ${subscription.name}`
    : `New listing · ${subscription.name}`;
  const body = [price, location, item?.title].filter(Boolean).join(' · ').slice(0, 220)
    || (String(subscription.language || '').startsWith('ru') ? 'Новое объявление по вашему фильтру' : 'A new listing matches your filter');
  return {title, body};
}

async function scanSubscription(subscription) {
  const items = await fetchMatches(subscription);
  if (!subscription.initialized) {
    await primeSeen(subscription, items);
    return 0;
  }

  let sent = 0;
  for (const item of [...items].reverse()) {
    if (sent >= MAX_NOTIFICATIONS_PER_SCAN) break;
    const key = listingKey(item);
    if (!key || await seen(subscription.id, key)) continue;
    if (await delivered(subscription.device_id, key)) {
      await markSeen(subscription.id, key);
      continue;
    }

    const {title, body} = notificationText(subscription, item);
    try {
      await sendMobilePush({
        token: subscription.push_token,
        title,
        body,
        data: {
          type: 'listing',
          publicId: item.publicId ?? '',
          source: item.source ?? '',
          country: item.country ?? '',
          listingId: item.id ?? '',
          presetId: subscription.preset_id,
        },
      });
      await markDelivered(subscription, key);
      await markSeen(subscription.id, key);
      sent += 1;
    } catch (err) {
      console.warn(`[mobile-push] ${subscription.device_id}/${key} failed:`, err?.message ?? err);
      const invalidToken = ['NOT_FOUND', 'UNREGISTERED'].includes(String(err?.firebaseStatus || '').toUpperCase())
        || String(err?.message || '').includes('UNREGISTERED');
      if (invalidToken) {
        await pool.query(`
          UPDATE ${SCHEMA}.mobile_devices
          SET enabled = FALSE, updated_at = NOW()
          WHERE device_id = $1;
        `, [subscription.device_id]);
        break;
      }
      throw err;
    }
  }
  await pool.query(`
    UPDATE ${SCHEMA}.mobile_subscriptions SET last_checked_at = NOW() WHERE id = $1;
  `, [subscription.id]);
  return sent;
}

export async function scanMobileSubscriptions() {
  if (scanning || !mobilePushConfigured()) return;
  scanning = true;
  try {
    for (const subscription of await enabledSubscriptions()) {
      try {
        await scanSubscription(subscription);
      } catch (err) {
        console.warn(`[mobile-subscriptions] scan #${subscription.id} failed:`, err?.message ?? err);
      }
    }
  } finally {
    scanning = false;
  }
}

export function startMobileSubscriptionScanner() {
  if (!mobilePushConfigured()) {
    console.log('[mobile-push] transport disabled; set FIREBASE_SERVICE_ACCOUNT_B64 to send apartment pushes');
    return;
  }
  if (scanTimer) return;
  console.log(`[mobile-push] scanning apartment presets every ${Math.round(POLL_MS / 1000)}s`);
  scanTimer = setInterval(() => void scanMobileSubscriptions(), POLL_MS);
  scanTimer.unref?.();
  void scanMobileSubscriptions();
}

export function stopMobileSubscriptionScanner() {
  if (scanTimer) clearInterval(scanTimer);
  scanTimer = undefined;
}
