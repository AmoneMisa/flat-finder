import test from 'node:test';
import assert from 'node:assert/strict';

import {applyFilters, looksParkingOnly, makeListing} from '../src/normalize.js';
import {parseResidentialComplex} from '../src/textparse-overrides.js';

test('explicit daily rent overrides a generic long-rent source classification and is hidden', () => {
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
  assert.equal(applyFilters([listing], {}).length, 0);
  assert.ok(listing.title.length < 90);
  assert.doesNotMatch(listing.title, /Свободна сегодня/iu);
});

test('parking-space inventory is rejected without rejecting apartments that merely have parking', () => {
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
  assert.equal(applyFilters([parking], {}).length, 0);

  assert.equal(
    looksParkingOnly('Сдам 2-комнатную квартиру в ЖК Аркадия, есть собственное парковочное место'),
    false,
  );
});

test('Odessa Pearl residential complexes normalize numeric and Ukrainian ordinal forms', () => {
  assert.equal(parseResidentialComplex('Сдам квартиру, 35 жемчужина, Каманина'), '35 Жемчужина');
  assert.equal(parseResidentialComplex('Свободна 6я жемчужина, Аркадия'), '6 Жемчужина');
  assert.equal(
    parseResidentialComplex("Великий + Середній Фонтани, ЖК Тридцять п'ята перлина, вул. Літературна, 8"),
    '35 Жемчужина',
  );
});

test('ID-like titles are replaced with a structured residential title', () => {
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

test('normal concise source titles remain untouched', () => {
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

test('sale listings keep sale classification even when copy mentions daily-rental potential', () => {
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
  assert.equal(applyFilters([listing], {}).length, 1);
});
