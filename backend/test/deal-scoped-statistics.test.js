import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('../src/postgres-search.js', import.meta.url), 'utf8');

test('listing geography statistics are split by sale, rent, short rent and room rent', () => {
  assert.match(source, /AS deal_key/u);
  assert.match(source, /GROUP BY GROUPING SETS/u);
  assert.match(source, /\(v\.deal_key, geo\.dimension, geo\.label\)/u);
  assert.match(source, /AS geographies_by_deal/u);
  assert.match(source, /geographiesByDeal: countOrStatsResult\.rows\[0\]\?\.geographies_by_deal/u);
  assert.match(source, /WHEN data @> '\{"roomOnly":true\}'::jsonb THEN 'roomRent'/u);
});
