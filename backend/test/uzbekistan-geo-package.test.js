import test from 'node:test';
import assert from 'node:assert/strict';

import {
  applyGeoCatalogBroadAnchor,
  applyGeoCatalogCityFallback,
  applyGeoCatalogExactAnchor,
} from '../src/geo-catalog.js';
import { applyReverseGeo } from '../src/reverse-geo.js';

test('canonicalizes Uzbekistan city aliases and fills city fallback from geo-catalog', () => {
  const listing = { id: 'samarkand', city: 'Самарканд', lat: null, lng: null };

  assert.equal(applyGeoCatalogCityFallback(listing, { code: 'UZ' }), true);
  assert.equal(listing.city, 'Samarkand');
  assert.ok(Number.isFinite(listing.lat));
  assert.ok(Number.isFinite(listing.lng));
  assert.equal(listing.locationSource, 'city');
  assert.equal(listing.locationAccuracyM, 8000);
});

test('geo-catalog covers Uzbekistan cities beyond the old seven-city list', () => {
  const listings = [
    { id: 'qarshi', city: 'Карши' },
    { id: 'khiva', city: 'Xiva' },
    { id: 'chirchiq', city: 'Чирчик' },
  ];

  for (const listing of listings) {
    assert.equal(applyGeoCatalogCityFallback(listing, { code: 'UZ' }), true);
  }

  assert.deepEqual(listings.map(({ city }) => city), ['Qarshi', 'Khiva', 'Chirchiq']);
  for (const listing of listings) {
    assert.ok(Number.isFinite(listing.lat));
    assert.ok(Number.isFinite(listing.lng));
    assert.equal(listing.locationSource, 'city');
  }
});

test('stable exact and broad Uzbekistan entities resolve locally when catalogued', () => {
  const metro = { city: 'Тошкент', metro: 'Chorsu' };
  assert.equal(applyGeoCatalogExactAnchor(metro, { code: 'UZ' }), true);
  assert.equal(metro.city, 'Tashkent');
  assert.equal(metro.locationSource, 'metro');

  const district = { city: 'Tashkent', district: 'Chilanzar' };
  assert.equal(applyGeoCatalogBroadAnchor(district, { code: 'UZ' }), true);
  assert.equal(district.locationSource, 'district');
});

test('reverse-geocoding does not invent forward city coordinates', async () => {
  const listing = { id: 'qarshi-pipeline', city: 'Карши', lat: null, lng: null };

  const filled = await applyReverseGeo([listing], { code: 'UZ' }, 0);

  assert.equal(filled, 0);
  assert.equal(listing.lat, null);
  assert.equal(listing.lng, null);
});
