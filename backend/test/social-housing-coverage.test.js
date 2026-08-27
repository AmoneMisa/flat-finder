import assert from 'node:assert/strict';
import test from 'node:test';

import { classifyHousingOffer } from '../src/scrapers/social.js';
import { buildThreadsHousingCoverage, UKRAINE_OBLASTS } from '../src/social-search-coverage.js';

test('social housing covers all 24 Ukrainian oblasts without assigning an oblast centre as city', () => {
  assert.equal(UKRAINE_OBLASTS.length, 24);
  const coverage = buildThreadsHousingCoverage();
  for (const oblast of UKRAINE_OBLASTS) {
    const matches = coverage.filter((target) => target.country === 'UA' && target.region === oblast.region);
    assert.equal(matches.length, 3, `${oblast.ua} should have three package-backed housing searches`);
    assert.ok(matches.every((target) => !target.city), `${oblast.ua} must remain oblast-wide`);
  }
});

test('housing coverage includes package-backed searches in local languages', () => {
  const coverage = buildThreadsHousingCoverage();
  for (const query of [
    'аренда Узбекистан',
    'аренда Ташкент',
    'квартира Ташкент',
    'ijara Toshkent',
    'аренда Алматы',
    'жалға Алматы',
    'chirie București',
    'оренда Україна',
  ]) {
    assert.ok(coverage.some((target) => target.target.toLocaleLowerCase() === query.toLocaleLowerCase()), `missing ${query}`);
  }
});

test('social housing classifier accepts offers and rejects demand in supported languages', () => {
  assert.equal(classifyHousingOffer('Сдам 2-комнатную квартиру в Ташкенте, цена 500$'), 'longRent');
  assert.equal(classifyHousingOffer('Продам квартиру в Алматы, 2 комнаты, 45 м2'), 'sale');
  assert.equal(classifyHousingOffer('Здам квартиру у Львові, 18000 грн на місяць'), 'longRent');
  assert.equal(classifyHousingOffer('Închiriez apartament în București, 600 EUR'), 'longRent');
  assert.equal(classifyHousingOffer('Vând apartament în Cluj-Napoca, 85000 EUR'), 'sale');
  assert.equal(classifyHousingOffer('Uy ijaraga beriladi Toshkent, 500 USD'), 'longRent');
  assert.equal(classifyHousingOffer('Пәтер жалға беріледі Алматы, 250000 теңге'), 'longRent');

  assert.equal(classifyHousingOffer('Ищу квартиру в Ташкенте, сниму на год'), null);
  assert.equal(classifyHousingOffer('Шукаю квартиру у Києві, зніму на тривалий термін'), null);
  assert.equal(classifyHousingOffer('Caut apartament să închiriez în București'), null);
  assert.equal(classifyHousingOffer('Куплю квартиру в Алматы'), null);
});
