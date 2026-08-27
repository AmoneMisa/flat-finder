import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const source = readFileSync(
  new URL('../src/listing-item-routes.js', import.meta.url),
  'utf8',
);

test('direct OLX listing open uses one live offer fetch for reload and availability', () => {
  assert.match(source, /import \{recordListingAvailability\} from '\.\/availability\.js'/);
  assert.doesNotMatch(source, /verifyListingAvailability/);

  const fetchMatches = source.match(/fetchOlxOffer\(country, id\)/g) || [];
  assert.equal(fetchMatches.length, 1, 'direct open must make one live OLX offer request');
  assert.match(source, /const listing = await fetchOlxOffer\(country, id\);/);
});

test('missing live OLX offer records inactive state and returns 404', () => {
  assert.match(
    source,
    /if \(!listing\) \{[\s\S]*?recordListingAvailability\(\{[\s\S]*?status: 'inactive',[\s\S]*?reason: 'offer_not_found',[\s\S]*?\}\);[\s\S]*?return res\.status\(404\)\.json\(\{error: 'Listing no longer available'\}\);[\s\S]*?\}/,
  );
});

test('successful live OLX offer records active availability', () => {
  assert.match(
    source,
    /recordListingAvailability\(\{[\s\S]*?status: 'active',[\s\S]*?reason: 'offer_reload',[\s\S]*?\}\);/,
  );
});
