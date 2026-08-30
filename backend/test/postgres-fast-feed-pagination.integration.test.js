import assert from 'node:assert/strict';
import test from 'node:test';

import {closeDb, pool, upsertListings} from '../src/db.js';
import {assertDatabaseReady} from '../src/db-ready.js';
import {searchPostgresListings} from '../src/postgres-search-fast.js';

const enabled = process.env.TEST_POSTGRES_SEARCH === '1';
const SOURCE = 'fast-feed-pagination-test';
const COUNTRY = 'QX';

function decodeCursor(value) {
  return JSON.parse(Buffer.from(String(value), 'base64url').toString('utf8'));
}

test('fast default feed carries count and avoids an empty terminal cursor page', {skip: !enabled}, async () => {
  await assertDatabaseReady();
  await pool.query('DELETE FROM listings WHERE source = $1', [SOURCE]);

  const now = Date.now();
  await upsertListings([
    {
      id: 'fast-feed-1',
      source: SOURCE,
      country: COUNTRY,
      title: 'Fast feed pagination one',
      description: 'Unique fast feed pagination fixture one.',
      propertyType: 'flat',
      dealType: 'longRent',
      price: 401,
      currency: 'USD',
      city: 'Fast Feed City',
      createdAt: new Date(now - 60_000).toISOString(),
      commercial: false,
    },
    {
      id: 'fast-feed-2',
      source: SOURCE,
      country: COUNTRY,
      title: 'Fast feed pagination two',
      description: 'Unique fast feed pagination fixture two.',
      propertyType: 'flat',
      dealType: 'longRent',
      price: 402,
      currency: 'USD',
      city: 'Fast Feed City',
      createdAt: new Date(now - 120_000).toISOString(),
      commercial: false,
    },
    {
      id: 'fast-feed-3',
      source: SOURCE,
      country: COUNTRY,
      title: 'Fast feed pagination three',
      description: 'Unique fast feed pagination fixture three.',
      propertyType: 'flat',
      dealType: 'longRent',
      price: 403,
      currency: 'USD',
      city: 'Fast Feed City',
      createdAt: new Date(now - 180_000).toISOString(),
      commercial: false,
    },
  ]);

  const filters = {
    propertyType: 'any',
    dealType: 'any',
    agency: 'any',
    audience: 'any',
    sources: [],
    sort: 'newest',
    limit: 1,
    offset: 0,
    maxAgeDays: 14,
  };

  const first = await searchPostgresListings({filters, countries: [COUNTRY], rates: {USD: 1}});
  assert.equal(first.searchPath, 'postgres-feed-members');
  assert.equal(first.count, 3);
  assert.equal(first.listings.length, 1);
  assert.equal(first.listings[0]?.id, 'fast-feed-1');
  assert.ok(first.nextCursor);
  assert.equal(decodeCursor(first.nextCursor).c, 3);

  const second = await searchPostgresListings({
    filters: {...filters, cursor: first.nextCursor, offset: 999},
    countries: [COUNTRY],
    rates: {USD: 1},
  });
  assert.equal(second.count, 3);
  assert.equal(second.listings.length, 1);
  assert.equal(second.listings[0]?.id, 'fast-feed-2');
  assert.ok(second.nextCursor);
  assert.equal(decodeCursor(second.nextCursor).c, 3);

  const third = await searchPostgresListings({
    filters: {...filters, cursor: second.nextCursor, offset: 999},
    countries: [COUNTRY],
    rates: {USD: 1},
  });
  assert.equal(third.count, 3);
  assert.equal(third.listings.length, 1);
  assert.equal(third.listings[0]?.id, 'fast-feed-3');
  assert.equal(third.nextCursor, null);

  await pool.query('DELETE FROM listings WHERE source = $1', [SOURCE]);
  await closeDb();
});
