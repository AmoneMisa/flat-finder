import test from 'node:test';
import assert from 'node:assert/strict';

import { geocodeCandidates, poiDistanceM } from '../src/geocode.js';

const country = {
  name: 'Uzbekistan',
  cities: ['Tashkent', 'Samarkand'],
  center: { lat: 41.3111, lng: 69.2797 },
};

test('orders geocoding signals from exact to broad with metro above nearby POI', () => {
  const listing = {
    id: 'priority',
    city: 'Tashkent',
    district: 'Uchtepa',
    area: 'Chilanzar-12',
    nearbyShops: ['Korzinka'],
    nearby: ['Bobur Park'],
    metro: 'Chilonzor',
    address: 'Bunyodkor shoh kochasi 10',
  };

  assert.deepEqual(
    geocodeCandidates(listing, country).map((candidate) => candidate.source),
    ['address', 'metro', 'nearby', 'nearby', 'area', 'district', 'city'],
  );
});

test('uses area/kvartal before district and city', () => {
  const listing = {
    id: 'area',
    city: 'Tashkent',
    district: 'Yakkasaray',
    kvartal: 'Glinka',
  };

  const candidates = geocodeCandidates(listing, country);
  assert.deepEqual(candidates.map((candidate) => candidate.source), ['area', 'district', 'city']);
  assert.match(candidates[0].q, /Glinka/);
  assert.match(candidates[0].q, /Yakkasaray/);
});

test('adds an explicit city candidate instead of relying on the country center', () => {
  const listing = { id: 'samarkand', city: 'Samarkand' };
  const candidates = geocodeCandidates(listing, country);

  assert.equal(candidates.length, 1);
  assert.equal(candidates[0].source, 'city');
  assert.equal(candidates[0].q, 'Samarkand, Uzbekistan');
});

test('keeps stated POI distance as geocoding uncertainty', () => {
  const listing = {
    id: 'distance',
    city: 'Tashkent',
    district: 'Yunusabad',
    nearbyShops: ['Korzinka'],
    title: 'Квартира в аренду',
    description: '500 м от Корзинки, рядом с парком',
  };

  assert.equal(poiDistanceM(listing, 'Korzinka'), 500);
  const nearby = geocodeCandidates(listing, country).find((candidate) => candidate.source === 'nearby');
  assert.equal(nearby.accuracyM, 500);
});

test('converts kilometre POI distance to metres', () => {
  const listing = { description: 'Korzinka 1.2 km' };
  assert.equal(poiDistanceM(listing, 'Korzinka'), 1200);
});
