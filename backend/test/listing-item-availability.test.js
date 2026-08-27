import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const source = readFileSync(
  new URL('../src/listing-item-routes.js', import.meta.url),
  'utf8',
);

test('direct OLX listing open reuses a fresh active result for sixty minutes', () => {
  assert.match(source, /readFreshActiveListing/);
  assert.match(source, /const cached = await readFreshActiveListing\(\{source, country: code, id\}\)/);
  assert.match(source, /if \(cached\) \{[\s\S]*?cached: true[\s\S]*?\}/);

  const fetchMatches = source.match(/fetchOlxOffer\(country, id\)/g) || [];
  assert.equal(fetchMatches.length, 1, 'direct open must make one live OLX offer request');
  assert.match(source, /const listing = await fetchOlxOffer\(country, id\);/);
  assert.ok(
    source.indexOf('if (cached)') < source.indexOf('fetchOlxOffer(country, id)'),
    'fresh active cache must be checked before touching OLX',
  );
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
  assert.match(source, /const availability = await recordListingAvailability/);
  assert.match(source, /availability\.publicId \? \{publicId: availability\.publicId\}/);
  assert.match(source, /cached: false/);
});
