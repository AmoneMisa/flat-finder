import assert from 'node:assert/strict';
import test from 'node:test';

import {closeDb, pool, upsertListings} from '../src/db.js';
import {assertDatabaseReady} from '../src/db-ready.js';
import {searchPostgresMapPoints} from '../src/map-feed.js';
import {searchPostgresListings} from '../src/postgres-search.js';

const enabled = process.env.TEST_POSTGRES_SEARCH === '1';
const SOURCE = 'perf-hardening-test';

test('typed filters, normalized relations and radius prefilter preserve listing/map semantics', {skip: !enabled}, async () => {
  await assertDatabaseReady();
  await pool.query('DELETE FROM listings WHERE source = $1', [SOURCE]);

  const now = new Date().toISOString();
  const base = {
    source: SOURCE,
    country: 'UA',
    title: 'Performance hardening test',
    description: 'Synthetic integration listing for PostgreSQL search hardening.',
    propertyType: 'flat',
    dealType: 'longRent',
    byAgency: false,
    price: 500,
    currency: 'USD',
    rooms: 2,
    areaSqm: 55,
    city: 'Odesa',
    district: 'Prymorskyi',
    createdAt: now,
    commercial: false,
    bedrooms: 2,
    floor: 4,
    totalFloors: 12,
    buildingYear: 2021,
    commission: false,
    commissionPercent: 0,
    metroDistanceM: 650,
    microdistrict: 'Arkadia',
    localAreas: ['Arkadia'],
    developmentAreas: ['French Boulevard'],
    informalAreas: ['Seaside'],
    nearbyPlaces: [
      {kind: 'park', distanceM: 280},
      {kind: 'school', distanceM: 600},
    ],
    lat: 46.4310,
    lng: 30.7610,
    photo: 'https://example.com/perf-hardening.jpg',
  };

  try {
    await upsertListings([
      {...base, id: 'near'},
      {...base, id: 'far', lat: 46.60, lng: 30.95},
      {...base, id: 'wrong-bedroom', bedrooms: 1, lat: 46.4312, lng: 30.7612},
    ]);

    const relationRows = await pool.query(`
      SELECT term_type, normalized_name
      FROM listing_location_terms term
      JOIN listings listing ON listing.id = term.listing_id
      WHERE listing.source = $1 AND listing.source_id = 'near'
      ORDER BY term_type, normalized_name
    `, [SOURCE]);
    assert.ok(relationRows.rows.some((row) => row.term_type === 'microdistrict' && row.normalized_name === 'arkadia'));
    assert.ok(relationRows.rows.some((row) => row.term_type === 'development_area' && row.normalized_name === 'french boulevard'));

    const filters = {
      propertyType: 'any',
      dealType: 'any',
      agency: 'any',
      audience: 'any',
      sources: [SOURCE],
      city: 'Odesa',
      bedroomsMin: 2,
      floorMin: 4,
      totalFloorsMin: 10,
      yearMin: 2020,
      commissionPercentMax: 0,
      metroMaxM: 700,
      microdistrict: 'Arkadia',
      nearbyKind: 'park',
      nearbyMaxM: 300,
      centerLat: 46.4310,
      centerLng: 30.7610,
      radiusM: 1200,
      sort: 'newest',
      limit: 20,
      offset: 0,
    };

    const result = await searchPostgresListings({
      filters,
      countries: ['UA'],
      rates: {USD: 1},
    });
    assert.equal(result.count, 1);
    assert.deepEqual(result.listings.map((item) => item.id), ['near']);

    const map = await searchPostgresMapPoints({
      filters,
      countries: ['UA'],
      rates: {USD: 1},
    });
    assert.equal(map.count, 1);
    assert.equal(map.pages, 1);
    assert.equal(map.points.length, 1);
    assert.equal(map.points[0].id, 'near');
    assert.equal(map.points[0].lat, base.lat);
    assert.equal(map.points[0].lng, base.lng);
  } finally {
    await pool.query('DELETE FROM listings WHERE source = $1', [SOURCE]);
    await closeDb();
  }
});
