import test from 'node:test';
import assert from 'node:assert/strict';

import {assertDatabaseReady} from '../src/db-ready.js';
import {closeDb, pool, upsertListings} from '../src/db.js';
import {applyListingFilters} from '../src/legacy-listing-filter.js';
import {searchPostgresListings} from '../src/postgres-search.js';

const enabled = process.env.TEST_POSTGRES_SEARCH === '1';
const SOURCE = 'filter-parity-test';
const COUNTRY = 'XY';

function listing(id, overrides = {}) {
  return {
    id,
    source: SOURCE,
    country: COUNTRY,
    title: `Parity ${id}`,
    description: 'Filter parity integration listing',
    propertyType: 'flat',
    dealType: 'longRent',
    byAgency: false,
    price: 300,
    currency: 'USD',
    rooms: 2,
    bedrooms: 1,
    areaSqm: 50,
    city: 'Parity City',
    createdAt: new Date().toISOString(),
    commercial: false,
    ...overrides,
  };
}

function baseFilters(overrides = {}) {
  return {
    propertyType: 'any',
    dealType: 'any',
    agency: 'any',
    audience: 'any',
    sources: [],
    city: '',
    district: '',
    metro: '',
    limit: 60,
    offset: 0,
    ...overrides,
  };
}

async function postgresIds(filters, rates = {USD: 1, UAH: 40}) {
  const result = await searchPostgresListings({
    filters,
    countries: [COUNTRY],
    rates,
  });
  return result.listings.map((item) => item.id).sort();
}

function legacyIds(listings, filters, rates = {USD: 1, UAH: 40}) {
  return applyListingFilters(listings, filters, rates)
    .map((item) => item.id)
    .sort();
}

test('legacy fallback and PostgreSQL search share core filter semantics', {skip: !enabled}, async () => {
  await assertDatabaseReady();
  await pool.query('DELETE FROM listings WHERE source = $1 AND country = $2', [SOURCE, COUNTRY]);

  const listings = [
    listing('long-owner-usd', {
      airConditioner: true,
      petsAllowed: true,
      childrenAllowed: true,
    }),
    listing('short-owner-uah', {
      dealType: 'shortRent',
      price: 10_000,
      currency: 'UAH',
      airConditioner: true,
      petsAllowed: true,
      childrenAllowed: true,
    }),
    listing('long-agency', {
      byAgency: true,
      price: 450,
      airConditioner: true,
    }),
    listing('no-ac', {
      price: 250,
      airConditioner: false,
    }),
    listing('commercial', {
      price: 100,
      commercial: true,
    }),
  ];

  await upsertListings(listings);

  try {
    const cases = [
      baseFilters({dealType: 'shortRent'}),
      baseFilters({dealType: 'longRent', agency: 'owner'}),
      baseFilters({priceMax: 320, priceCurrency: 'USD'}),
      baseFilters({airConditioner: true}),
      baseFilters({pets: true, children: true}),
      baseFilters({roomsMin: 2, roomsMax: 2, areaMin: 45, areaMax: 55}),
    ];

    for (const filters of cases) {
      assert.deepEqual(
        await postgresIds(filters),
        legacyIds(listings, filters),
        `filter parity failed for ${JSON.stringify(filters)}`,
      );
    }
  } finally {
    await pool.query('DELETE FROM listings WHERE source = $1 AND country = $2', [SOURCE, COUNTRY]);
    await closeDb();
  }
});
