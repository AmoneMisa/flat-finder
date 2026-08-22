import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { COUNTRIES } from '../src/countries.js';

const OBLAST_CENTRES = [
  'Vinnytsia', 'Lutsk', 'Dnipro', 'Donetsk', 'Zhytomyr', 'Uzhhorod',
  'Zaporizhzhia', 'Ivano-Frankivsk', 'Kyiv', 'Kropyvnytskyi', 'Luhansk',
  'Lviv', 'Mykolaiv', 'Odesa', 'Poltava', 'Rivne', 'Sumy', 'Ternopil',
  'Kharkiv', 'Kherson', 'Khmelnytskyi', 'Cherkasy', 'Chernivtsi', 'Chernihiv',
];

test('all Ukrainian oblast centres have targeted OLX coverage', () => {
  const targets = new Set((COUNTRIES.UA.olxCities || []).map((item) => item.city));
  for (const city of OBLAST_CENTRES) {
    assert.ok(targets.has(city), `${city} must be an OLX target`);
  }
});

test('Odesa breadth also crawls separate Fontanka and Kryzhanivka OLX pages', () => {
  const odesaSlugs = (COUNTRIES.UA.olxCities || [])
    .filter((item) => item.city === 'Odesa')
    .map((item) => item.slug);
  assert.ok(odesaSlugs.includes('odessa'));
  assert.ok(odesaSlugs.includes('fontanka'));
  assert.ok(odesaSlugs.includes('kryzhanovka'));
});

test('compose makes the full UA target list a bounded every-refresh breadth pass', () => {
  const compose = readFileSync(new URL('../../docker-compose.yml', import.meta.url), 'utf8');
  assert.match(compose, /OLX_UA_CITIES_PER_RUN=\$\{OLX_UA_CITIES_PER_RUN:-40\}/);
  assert.match(compose, /OLX_UA_CITY_MAX_PAGES=\$\{OLX_UA_CITY_MAX_PAGES:-1\}/);
  assert.ok(COUNTRIES.UA.olxCities.length <= 40, 'all configured UA targets must fit in one run');
});
