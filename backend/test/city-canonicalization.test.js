import test from 'node:test';
import assert from 'node:assert/strict';

import { makeListing } from '../src/normalize.js';

function listing(city) {
  return makeListing({
    id: `city-${city}`,
    source: 'telegram',
    country: 'UZ',
    city,
    title: 'Квартира в аренду',
    description: '',
  });
}

test('canonicalizes Tashkent aliases before geocoding', () => {
  assert.equal(listing('Toshkent').city, 'Tashkent');
  assert.equal(listing('Ташкент').city, 'Tashkent');
  assert.equal(listing('tashkent').city, 'Tashkent');
});

test('keeps an unknown source city instead of discarding it', () => {
  assert.equal(listing('Yangiyul').city, 'Yangiyul');
});
