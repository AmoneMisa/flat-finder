import test from 'node:test';
import assert from 'node:assert/strict';

import { applyStructuredAddressFields } from '../src/structured-address.js';

test('canonical dictionary street gains direct house fields from listing prose', () => {
  const listing = {
    street: 'Воробкевича',
    address: null,
    title: 'Продаж квартири',
    description: 'Чернівці, Воробкевича 12, поруч парк. Площа 68 м2.',
  };

  applyStructuredAddressFields(listing);

  assert.equal(listing.street, 'Воробкевича');
  assert.equal(listing.houseNumber, '12');
  assert.equal(listing.building, null);
  assert.equal(listing.address, 'Воробкевича 12');
});

test('source address is split into stable direct fields', () => {
  const listing = {
    address: "Shota Rustaveli ko'chasi 58, korpus 2",
    title: '',
    description: '',
  };

  applyStructuredAddressFields(listing);

  assert.equal(listing.street, 'Shota Rustaveli');
  assert.equal(listing.houseNumber, '58');
  assert.equal(listing.building, '2');
  assert.equal(listing.address, 'Shota Rustaveli 58 корп. 2');
});

test('unrelated prices and phones do not become house numbers', () => {
  const listing = {
    street: 'Воробкевича',
    title: 'Квартира на Воробкевича',
    description: 'Площа 68 м2. Ціна 95000. Телефон +380 50 123 45 67.',
  };

  applyStructuredAddressFields(listing);

  assert.equal(listing.street, 'Воробкевича');
  assert.equal(listing.houseNumber, null);
  assert.equal(listing.address, 'Воробкевича');
});
