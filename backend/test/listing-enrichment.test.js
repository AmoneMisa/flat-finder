import test from 'node:test';
import assert from 'node:assert/strict';
import {enrichListingDetails, __listingEnrichmentTest as detail} from '../src/listing-enrichment.js';

test('extracts bedrooms, bathrooms and 5\\5 floor notation', () => {
  const listing = enrichListingDetails({
    title: 'Квартира',
    description: 'Спальни: 3\nКоличество санузлов: 2\nЭтаж 5\\5',
    price: 700,
    currency: 'USD',
  });

  assert.equal(listing.bedrooms, 3);
  assert.equal(listing.bathrooms, 2);
  assert.equal(listing.floor, 5);
  assert.equal(listing.totalFloors, 5);
});

test('extracts realtor commission size in both word orders', () => {
  assert.equal(detail.parseCommissionPercent('Комиссия риелтора: 50%'), 50);
  assert.equal(detail.parseCommissionPercent('50 % риэлтору'), 50);
  assert.equal(detail.parseCommissionPercent('Риелтор 50/50'), 50);

  const listing = enrichListingDetails({
    title: 'Сдаётся квартира',
    description: 'Услуги риелтора 40%',
    commission: true,
    commissionPercent: null,
  });
  assert.equal(listing.commission, true);
  assert.equal(listing.commissionPercent, 40);
});

test('does not promote a phone number to address', () => {
  assert.equal(detail.normalizeAddressCandidate('+998 90 123 45 67'), null);
  assert.equal(detail.parseAddress('Адрес: +998 90 123 45 67\nТелефон для связи'), null);
  assert.equal(detail.parseAddress('Адрес: ул. Шота Руставели 12'), 'ул. Шота Руставели 12');
});

test('extracts cadastral availability and first rental', () => {
  assert.equal(detail.parseCadastral('Кадастр есть, документы готовы'), true);
  assert.equal(detail.parseCadastral('Продажа без кадастра'), false);
  assert.equal(detail.parseFirstRental('Первая сдача после ремонта'), true);
  assert.equal(detail.parseFirstRental('Сдаётся впервые'), true);
});

test('marks only explicitly single-woman low-price room shares as potentially unsafe', () => {
  const risky = enrichListingDetails({
    title: 'Подселение',
    description: 'Нужна только одна девушка, одно место в квартире',
    price: 80,
    currency: 'USD',
    roomOnly: true,
  });
  assert.equal(risky.potentiallyUnsafe, true);

  const normalPrice = enrichListingDetails({
    title: 'Подселение',
    description: 'Нужна только одна девушка, одно место в квартире',
    price: 250,
    currency: 'USD',
    roomOnly: true,
  });
  assert.equal(normalPrice.potentiallyUnsafe, false);

  const womenOnlyFlat = enrichListingDetails({
    title: 'Квартира для девушек',
    description: 'Только девушки, сдаётся целая квартира',
    price: 80,
    currency: 'USD',
    roomOnly: false,
  });
  assert.equal(womenOnlyFlat.potentiallyUnsafe, false);
});
