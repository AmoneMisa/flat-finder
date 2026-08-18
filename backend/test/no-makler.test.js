import test from 'node:test';
import assert from 'node:assert/strict';

import { makeListing } from '../src/normalize.js';
import { classifyAgency } from '../src/textparse.js';

const text = `Квартира ЖК NRG BAXT БЕЗ МАКЛЕР!\n\nСдается квартира порядочным людям и иностранцам со всеми удобствами.`;

test('no-makler listing has no commission and clean residential-complex name', () => {
  const listing = makeListing({
    id: 'nrg-baxt-no-makler',
    source: 'olx',
    country: 'UZ',
    title: 'Квартира ЖК NRG BAXT',
    description: 'БЕЗ МАКЛЕР!\nСдается квартира порядочным людям и иностранцам со всеми удобствами.',
    byAgency: classifyAgency(text),
  });

  assert.equal(listing.byAgency, false);
  assert.equal(listing.commission, false);
  assert.equal(listing.commissionPercent, 0);
  assert.equal(listing.residenceComplex, 'NRG BAXT');
});
