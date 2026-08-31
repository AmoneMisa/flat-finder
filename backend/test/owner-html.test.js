import test from 'node:test';
import assert from 'node:assert/strict';

import { COUNTRIES } from '../src/countries.js';
import { extractKnownOwnerHtml } from '../src/scrapers/owner-html.js';

test('owner SSR fallback extracts a rental card with stable detail URL', () => {
  const html = [
    '<article>',
    '<a href="/en/listings/abc"><h3>Chilanzar apartment</h3></a>',
    '<p>Rent Tashkent 2 rooms 55 m² 5 000 000 UZS/mo</p>',
    '<img src="https://rentli.uz/images/abc.jpg">',
    '</article>',
  ].join('');

  const listings = extractKnownOwnerHtml(html, COUNTRIES.UZ, 'https://rentli.uz/en/listings');
  assert.equal(listings.length, 1);
  assert.equal(listings[0].rooms, 2);
  assert.equal(listings[0].areaSqm, 55);
  assert.equal(listings[0].byAgency, false);
  assert.match(listings[0].url, /\/en\/listings\/abc$/);
});

test('owner SSR fallback does not run on arbitrary custom domains', () => {
  const html = '<article><h3>Apartment</h3><p>Rent 2 rooms 500 USD</p></article>';
  assert.deepEqual(
    extractKnownOwnerHtml(html, COUNTRIES.UA, 'https://example.com/listings'),
    [],
  );
});
