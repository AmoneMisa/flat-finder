import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';

import {canUseFastListingPath} from '../src/postgres-search-fast.js';

const baseFilters = {
  listingId: '932949554',
  sources: ['olx'],
  propertyType: 'any',
  dealType: 'any',
  agency: 'any',
  audience: 'any',
  maxAgeDays: 14,
  limit: 1,
  offset: 0,
};

test('exact source listing requests qualify for the indexed detail path', () => {
  assert.equal(canUseFastListingPath(baseFilters, ['UA'], null), true);
  assert.equal(canUseFastListingPath({...baseFilters, sources: []}, ['UA'], null), false);
  assert.equal(canUseFastListingPath(baseFilters, ['UA', 'UZ'], null), false);
  assert.equal(canUseFastListingPath({...baseFilters, priceMax: 500}, ['UA'], null), false);
  assert.equal(canUseFastListingPath({...baseFilters, includeStats: true}, ['UA'], null), false);
});

test('fast searches use one database request and exact lookups follow the unique index order', async () => {
  const source = await readFile(new URL('../src/postgres-search-fast.js', import.meta.url), 'utf8');

  assert.match(source, /l\.source = \$1[\s\S]*l\.country = \$2[\s\S]*l\.source_id = \$3/u);
  assert.match(source, /searchPath: 'postgres-listing-id'/u);
  assert.match(source, /FROM \(SELECT COUNT\(\*\)::int AS count FROM deduped\) totals/u);
  assert.match(source, /LEFT JOIN page p ON TRUE/u);
  assert.doesNotMatch(source, /Promise\.all/u);
});
