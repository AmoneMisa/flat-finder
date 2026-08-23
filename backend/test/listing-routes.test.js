import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parseListingFilters} from '../src/listing-routes.js';
import {applyListingFilters} from '../src/legacy-listing-filter.js';

const appSource = readFileSync(
  new URL('../src/app.js', import.meta.url),
  'utf8',
);
const serverSource = readFileSync(
  new URL('../src/server.js', import.meta.url),
  'utf8',
);
const listingRoutesSource = readFileSync(
  new URL('../src/listing-routes.js', import.meta.url),
  'utf8',
);

test('application composes listing routes while server owns no search orchestration', () => {
  assert.match(appSource, /installListingRoutes\(app\)/);
  assert.doesNotMatch(serverSource, /app\.get\('\/api\/listings'/);
  assert.doesNotMatch(serverSource, /searchPostgresListings/);
  assert.doesNotMatch(serverSource, /getListings\(/);

  assert.match(listingRoutesSource, /app\.get\('\/api\/listings'/);
  assert.match(listingRoutesSource, /tryPostgresSearch/);
  assert.match(listingRoutesSource, /legacySnapshotSearch/);
  assert.match(listingRoutesSource, /applyListingFilters/);
  assert.doesNotMatch(listingRoutesSource, /from '\.\/normalize\.js'/);
});

test('listing filters preserve the existing public query contract', () => {
  const filters = parseListingFilters({
    propertyType: 'flat',
    dealType: 'longRent',
    agency: 'owner',
    audience: 'family',
    priceMin: '100',
    priceMax: '900',
    priceCurrency: 'usd',
    roomsMin: '2',
    city: 'Odesa',
    query: 'center',
    sources: 'OLX,telegram,unknown',
    customSources: 'https://example.com/a,https://example.com/a,ftp://bad',
    pets: 'true',
    children: '1',
    limit: '999',
    offset: '20',
    cursor: 'abc',
  });

  assert.equal(filters.propertyType, 'flat');
  assert.equal(filters.dealType, 'longRent');
  assert.equal(filters.agency, 'owner');
  assert.equal(filters.audience, 'family');
  assert.equal(filters.priceMin, 100);
  assert.equal(filters.priceMax, 900);
  assert.equal(filters.priceCurrency, 'USD');
  assert.equal(filters.roomsMin, 2);
  assert.equal(filters.city, 'Odesa');
  assert.equal(filters.query, 'center');
  assert.deepEqual(filters.sources, ['olx', 'telegram']);
  assert.deepEqual(filters.customSources, ['https://example.com/a']);
  assert.equal(filters.pets, true);
  assert.equal(filters.children, true);
  assert.equal(filters.limit, 60);
  assert.equal(filters.offset, 20);
  assert.equal(filters.cursor, 'abc');
});

test('legacy fallback honors the public shortRent deal type', () => {
  const listings = [
    {
      id: 'short',
      source: 'olx',
      dealType: 'shortRent',
      propertyType: 'flat',
      commercial: false,
      createdAt: new Date().toISOString(),
    },
    {
      id: 'long',
      source: 'olx',
      dealType: 'longRent',
      propertyType: 'flat',
      commercial: false,
      createdAt: new Date().toISOString(),
    },
  ];

  const shortOnly = applyListingFilters(listings, {
    dealType: 'shortRent',
    propertyType: 'any',
    agency: 'any',
    audience: 'any',
    sources: [],
  });
  assert.deepEqual(shortOnly.map((listing) => listing.id), ['short']);

  const allDeals = applyListingFilters(listings, {
    dealType: 'any',
    propertyType: 'any',
    agency: 'any',
    audience: 'any',
    sources: [],
  });
  assert.deepEqual(allDeals.map((listing) => listing.id), ['short', 'long']);
});
