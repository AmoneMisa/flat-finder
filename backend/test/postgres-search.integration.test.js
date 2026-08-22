import test from 'node:test';
import assert from 'node:assert/strict';

import { closeDb, initDb, pool, upsertListings } from '../src/db.js';
import { initPostgresSearchSchema, searchPostgresListings } from '../src/postgres-search.js';

const enabled = process.env.TEST_POSTGRES_SEARCH === '1';

test('PostgreSQL fast path filters mixed-currency listings and paginates with a cursor', { skip: !enabled }, async () => {
  await initDb();
  await initPostgresSearchSchema();
  await pool.query(`DELETE FROM listings WHERE source = 'pg-search-test'`);

  const now = Date.now();
  const listing = (id, price, currency, city, airConditioner, minutesAgo) => ({
    id,
    source: 'pg-search-test',
    country: 'UA',
    title: `Test ${id}`,
    description: 'integration test listing',
    propertyType: 'flat',
    dealType: 'longRent',
    byAgency: false,
    price,
    currency,
    rooms: 2,
    areaSqm: 50,
    city,
    district: city === 'Odesa' ? 'Prymorskyi' : null,
    createdAt: new Date(now - minutesAgo * 60_000).toISOString(),
    commercial: false,
    airConditioner,
    parking: true,
  });

  await upsertListings([
    listing('usd-250', 250, 'USD', 'Odesa', true, 1),
    listing('uah-10000', 10_000, 'UAH', 'Odesa', true, 2),
    listing('usd-500', 500, 'USD', 'Odesa', true, 3),
    listing('kyiv-200', 200, 'USD', 'Kyiv', true, 4),
    listing('no-ac', 200, 'USD', 'Odesa', false, 5),
  ]);

  const filters = {
    propertyType: 'any',
    dealType: 'longRent',
    agency: 'any',
    audience: 'any',
    priceMax: 300,
    priceTolerance: 0,
    priceCurrency: 'USD',
    city: 'Odesa',
    cityAliases: ['Odesa'],
    airConditioner: true,
    sources: [],
    sort: 'newest',
    limit: 1,
    offset: 0,
  };

  const first = await searchPostgresListings({
    filters,
    countries: ['UA'],
    rates: { USD: 1, UAH: 40 },
  });

  assert.equal(first.count, 2);
  assert.equal(first.listings.length, 1);
  assert.equal(first.listings[0].id, 'usd-250');
  assert.ok(first.nextCursor);

  const second = await searchPostgresListings({
    filters: { ...filters, cursor: first.nextCursor, offset: 999 },
    countries: ['UA'],
    rates: { USD: 1, UAH: 40 },
  });

  assert.equal(second.count, 2);
  assert.equal(second.listings.length, 1);
  assert.equal(second.listings[0].id, 'uah-10000');

  const noEsMatches = await searchPostgresListings({
    filters: { ...filters, query: 'Test', cursor: '', offset: 0 },
    countries: ['UA'],
    rates: { USD: 1, UAH: 40 },
    searchMatches: { rank: new Map(), scores: new Map(), total: 0, truncated: false },
  });
  assert.equal(noEsMatches.count, 0);
  assert.equal(noEsMatches.listings.length, 0);

  await pool.query(`DELETE FROM listings WHERE source = 'pg-search-test'`);
  await closeDb();
});
