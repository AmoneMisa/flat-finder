import test from 'node:test';
import assert from 'node:assert/strict';

import { olxSegmentDealType } from '../src/olx-segment.js';

test('OLX sale segment maps to sale', () => {
  assert.equal(olxSegmentDealType('flat:sale'), 'sale');
});

test('OLX long-rent segment maps to longRent', () => {
  assert.equal(olxSegmentDealType('flat:longRent'), 'longRent');
});

test('unsupported segment does not become an authoritative scope', () => {
  assert.equal(olxSegmentDealType('flat:shortRent'), null);
});
