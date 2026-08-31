import test from 'node:test';
import assert from 'node:assert/strict';

import { realtorHousingSources } from '../src/realtor-housing-sources.js';
import { buildCrawlPlan } from '../src/queuePlan.js';

test('Domza is included in the curated Tashkent housing sources', () => {
  const domza = realtorHousingSources('UZ').find(
    (source) => source.key === 'domza-tashkent-rent',
  );

  assert.deepEqual(domza, {
    key: 'domza-tashkent-rent',
    url: 'https://domza.uz/offers',
    city: 'Tashkent',
  });
});

test('Domza is scheduled as a curated custom-source crawl', () => {
  const { tasks } = buildCrawlPlan({ shardCount: 2 });
  const domza = tasks.find((task) => task.segment === 'domza-tashkent-rent');

  assert.ok(domza);
  assert.equal(domza.type, 'flat.custom.url');
  assert.equal(domza.country, 'UZ');
  assert.equal(domza.city, 'Tashkent');
  assert.equal(domza.url, 'https://domza.uz/offers');
  assert.equal(domza.curated, true);
});
