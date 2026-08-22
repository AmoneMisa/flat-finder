import test from 'node:test';
import assert from 'node:assert/strict';

import { closeDb, initDb, pool, upsertListings } from '../src/db.js';
import {
  initAvailabilitySchema,
  recordListingAvailability,
  verifyListingAvailability,
} from '../src/availability.js';

const enabled = process.env.TEST_POSTGRES_SEARCH === '1';

test('listing availability state deactivates stale OLX rows and reuses fresh checks', { skip: !enabled }, async () => {
  await initDb();
  await initAvailabilitySchema();

  const id = 'availability-test-1';
  await pool.query(`DELETE FROM listings WHERE source = 'olx' AND country = 'UZ' AND source_id = $1`, [id]);

  await upsertListings([{
    id,
    source: 'olx',
    country: 'UZ',
    title: 'Availability test apartment',
    description: 'Synthetic integration-test listing',
    propertyType: 'flat',
    dealType: 'longRent',
    byAgency: false,
    price: 450,
    currency: 'USD',
    rooms: 2,
    areaSqm: 50,
    city: 'Tashkent',
    createdAt: new Date().toISOString(),
    url: `https://www.olx.uz/d/obyavlenie/test-${id}.html`,
  }]);

  await recordListingAvailability({
    source: 'olx',
    country: 'UZ',
    id,
    status: 'inactive',
    reason: 'http_404',
  });

  let state = await pool.query(`
    SELECT active, availability_status, availability_reason, availability_checked_at
    FROM listings
    WHERE source = 'olx' AND country = 'UZ' AND source_id = $1
  `, [id]);

  assert.equal(state.rows[0]?.active, false);
  assert.equal(state.rows[0]?.availability_status, 'inactive');
  assert.equal(state.rows[0]?.availability_reason, 'http_404');
  assert.ok(state.rows[0]?.availability_checked_at);

  await recordListingAvailability({
    source: 'olx',
    country: 'UZ',
    id,
    status: 'active',
    reason: 'offer_page',
  });

  const cached = await verifyListingAvailability([{
    source: 'olx',
    country: 'UZ',
    id,
  }]);

  assert.equal(cached.length, 1);
  assert.equal(cached[0]?.status, 'active');
  assert.equal(cached[0]?.reason, 'offer_page');
  assert.equal(cached[0]?.cached, true);

  state = await pool.query(`
    SELECT active, missed_runs
    FROM listings
    WHERE source = 'olx' AND country = 'UZ' AND source_id = $1
  `, [id]);
  assert.equal(state.rows[0]?.active, true);
  assert.equal(state.rows[0]?.missed_runs, 0);

  await pool.query(`DELETE FROM listings WHERE source = 'olx' AND country = 'UZ' AND source_id = $1`, [id]);
  await closeDb();
});
