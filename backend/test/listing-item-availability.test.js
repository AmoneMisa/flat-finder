import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const source = readFileSync(
  new URL('../src/listing-item-routes.js', import.meta.url),
  'utf8',
);

test('direct OLX listing open forces availability verification before reload', () => {
  assert.match(source, /import \{verifyListingAvailability\} from '\.\/availability\.js'/);
  assert.match(source, /verifyListingAvailability\(\[\s*\{source, country: code, id\},\s*\], \{force: true\}\)/s);
  assert.match(source, /availability\?\.status === 'inactive'/);

  const availabilityIndex = source.indexOf('verifyListingAvailability');
  const reloadIndex = source.indexOf('fetchOlxOffer(country, id)');
  assert.ok(availabilityIndex >= 0);
  assert.ok(reloadIndex > availabilityIndex);
});

test('inactive direct OLX listing returns 404 without relying on source reload result', () => {
  assert.match(
    source,
    /if \(availability\?\.status === 'inactive'\) \{\s*return res\.status\(404\)\.json\(\{error: 'Listing no longer available'\}\);\s*\}/s,
  );
});
