import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { COUNTRIES } from '../src/countries.js';
import { looksParkingOnly, makeListing } from '../src/normalize.js';
import { applyListingFilters } from '../src/legacy-listing-filter.js';
import { parseResidentialComplex } from '../src/textparse-overrides.js';

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

test('compose allows every UA target to paginate until the freshness cutoff', () => {
  const compose = readFileSync(new URL('../../docker-compose.yml', import.meta.url), 'utf8');
  assert.match(compose, /OLX_UA_CITIES_PER_RUN=\$\{OLX_UA_CITIES_PER_RUN:-40\}/);
  assert.match(compose, /OLX_UA_CITY_MAX_PAGES=\$\{OLX_UA_CITY_MAX_PAGES:-1000\}/);
  assert.match(compose, /OLX_UA_CITY_BUDGET_MS=\$\{OLX_UA_CITY_BUDGET_MS:-600000\}/);
  assert.match(compose, /SOURCE_DEADLINE_MS=\$\{SOURCE_DEADLINE_MS:-7200000\}/);
  assert.match(compose, /OLX_LOOKBACK_DAYS=\$\{OLX_LOOKBACK_DAYS:-21\}/);
  assert.ok(COUNTRIES.UA.olxCities.length <= 40, 'all configured UA targets must fit in one run');
});

test('OLX fetcher ends pagination by age instead of by a one-page city limit', () => {
  const fetcher = readFileSync(new URL('../../olx-fetcher/app.py', import.meta.url), 'utf8');
  assert.match(fetcher, /LOOKBACK_DAYS = max\(1, int\(os\.environ\.get\("OLX_LOOKBACK_DAYS", "21"\)\)\)/);
  assert.match(fetcher, /def apply_lookback_page_stop\(ads\):/);
  assert.match(fetcher, /max\(known_dates\) < cutoff/);
  assert.match(fetcher, /\[\] if past_cutoff else ads/);
  assert.match(fetcher, /created_at%3Adesc/);
});

test('daily Odesa rentals override generic long-rent source metadata and remain selectable as shortRent', () => {
  const listing = makeListing({
    id: 'daily-pearl',
    source: 'telegram',
    country: 'UA',
    title: 'Сдам свои квартиры: Свободна сегодня!! 6я жемчужина, спальня и зал с диваном в 3м., 2+2, джакузи на двоих человек',
    description: '36 жемчужина, 19й этаж, 2 спальни плюс кухня-студия, от 4200/сутки, залог',
    propertyType: 'flat',
    dealType: 'longRent',
    city: 'Odesa',
    price: 4200,
    currency: 'UAH',
  });

  assert.equal(listing.dealType, 'shortRent');
  assert.equal(applyListingFilters([listing], {dealType: 'shortRent'}).length, 1);
  assert.equal(applyListingFilters([listing], {dealType: 'longRent'}).length, 0);
  assert.ok(listing.title.length < 90);
  assert.doesNotMatch(listing.title, /Свободна сегодня/iu);
});

test('parking-space inventory is noise while apartment parking stays an amenity', () => {
  const parkingText = `Сдаю свои\n🅿️ паркоместа в Жемчужинах (Каманина)\n27 Жемчужина\n32 Жемчужина\nЦена: 250 грн/сутки`;
  assert.equal(looksParkingOnly(parkingText), true);

  const parking = makeListing({
    id: 'parking',
    source: 'telegram',
    country: 'UA',
    title: 'Сдаю свои',
    description: parkingText,
    propertyType: 'flat',
    dealType: 'longRent',
    city: 'Odesa',
  });
  assert.equal(parking.commercial, true);
  assert.equal(applyListingFilters([parking], {}).length, 0);

  assert.equal(
    looksParkingOnly('Сдам 2-комнатную квартиру в ЖК Аркадия, есть собственное парковочное место'),
    false,
  );
});

test('Odesa Pearl complexes normalize numeric and Ukrainian ordinal forms', () => {
  assert.equal(parseResidentialComplex('Сдам квартиру, 35 жемчужина, Каманина'), '35 Жемчужина');
  assert.equal(parseResidentialComplex('Свободна 6я жемчужина, Аркадия'), '6 Жемчужина');
  assert.equal(
    parseResidentialComplex("Великий + Середній Фонтани, ЖК Тридцять п'ята перлина, вул. Літературна, 8"),
    '35 Жемчужина',
  );
});

test('ID-like titles are replaced with structured residential metadata', () => {
  const listing = makeListing({
    id: '1928765',
    source: 'telegram',
    country: 'UA',
    title: '⚡ 1928765',
    description: "🔑1k\n📍Великий + Середній Фонтани, ЖК Тридцять п'ята перлина, вул. Літературна, 8\n💵11000 грн + комунальні послуги, інтернет",
    propertyType: 'flat',
    dealType: 'longRent',
    city: 'Odesa',
  });

  assert.equal(listing.residenceComplex, '35 Жемчужина');
  assert.equal(listing.title, 'Квартира · 35 Жемчужина');
});

test('normal concise OLX titles remain untouched', () => {
  const sourceTitle = 'Оренда квартири в Аркадії Каманіна | 1-кімнатна квартира-студія';
  const listing = makeListing({
    id: 'olx-normal',
    source: 'olx',
    country: 'UA',
    title: sourceTitle,
    description: 'Здається затишна квартира в одному з найпопулярніших районів Одеси',
    propertyType: 'flat',
    dealType: 'longRent',
    city: 'Odesa',
  });

  assert.equal(listing.title, sourceTitle);
});

test('sale listings remain sales when copy mentions short-stay investment potential', () => {
  const listing = makeListing({
    id: 'sale-investment',
    source: 'olx',
    country: 'UA',
    title: 'Продам квартиру в Аркадии',
    description: 'Подходит для посуточной аренды и инвестиций',
    propertyType: 'flat',
    dealType: 'sale',
    city: 'Odesa',
  });

  assert.equal(listing.dealType, 'sale');
  assert.equal(applyListingFilters([listing], {}).length, 1);
});
