import test from 'node:test';
import assert from 'node:assert/strict';

import { UZ_CITY_COORDINATES } from '@whiteslove/parsing-lexicon/uz-geo-coordinates';
import { applyUzbekistanCoordinateFallbacks } from '../src/uzbekistan-geo.js';

test('canonicalizes Uzbekistan city aliases and fills only missing coordinates', () => {
  const listings = [
    { id: 'samarkand', city: 'Самарканд', lat: null, lng: null },
    {
      id: 'tashkent-source',
      city: 'Тошкент',
      lat: 41.3201,
      lng: 69.2812,
      locationSource: 'coordinates',
      locationAccuracyM: 25,
    },
  ];

  applyUzbekistanCoordinateFallbacks(listings);

  assert.equal(listings[0].city, 'Samarkand');
  assert.equal(listings[0].lat, UZ_CITY_COORDINATES.Samarkand.lat);
  assert.equal(listings[0].lng, UZ_CITY_COORDINATES.Samarkand.lng);
  assert.equal(listings[0].locationSource, 'city');
  assert.equal(listings[0].locationAccuracyM, 8000);

  assert.equal(listings[1].city, 'Tashkent');
  assert.equal(listings[1].lat, 41.3201);
  assert.equal(listings[1].lng, 69.2812);
  assert.equal(listings[1].locationSource, 'coordinates');
  assert.equal(listings[1].locationAccuracyM, 25);
});

test('covers package cities beyond the old Flat Finder seven-city list', () => {
  const listings = [
    { id: 'qarshi', city: 'Карши' },
    { id: 'khiva', city: 'Xiva' },
    { id: 'chirchiq', city: 'Чирчик' },
  ];

  applyUzbekistanCoordinateFallbacks(listings);

  assert.deepEqual(
    listings.map(({ city }) => city),
    ['Qarshi', 'Khiva', 'Chirchiq'],
  );
  for (const listing of listings) {
    assert.ok(Number.isFinite(listing.lat));
    assert.ok(Number.isFinite(listing.lng));
    assert.equal(listing.locationSource, 'city');
  }
});
