import test from 'node:test';
import assert from 'node:assert/strict';

import { makeListing } from '../src/normalize.js';
import { classifyAgency, parseFloor } from '../src/textparse.js';

const description = `Chilonzor 12
Shoxmed sentr
Xavas
2³/4/4
Xamma sharoit bor
Spalni,shkof,gilam, xaladenlik,kirmoshina,kuhinni kansaner bor
Uy yangi remontdan chiqqan.
Oila qo’yiladi.
Inastrans yoki davlat ishida ishlaydigan oila quyiladi
500$ Makler 50%
+998881090509`;

test('parses converted-room Uzbek Telegram shorthand and rental details', () => {
  const listing = makeListing({
    id: 'test',
    source: 'telegram',
    country: 'UZ',
    title: 'Chilonzor 12',
    description,
    price: 500,
    currency: 'USD',
    byAgency: classifyAgency(description),
  });

  assert.equal(listing.propertyType, 'flat');
  assert.equal(listing.rooms, 3);
  assert.equal(listing.floor, 4);
  assert.equal(listing.totalFloors, 4);
  assert.equal(listing.dealType, 'longRent');
  assert.equal(listing.byAgency, true);
  assert.equal(listing.commission, true);
  assert.equal(listing.commissionPercent, 50);
  assert.equal(listing.airConditioner, true);
  assert.equal(listing.furnished, true);
  assert.equal(listing.audience, 'family');
  assert.equal(listing.city, 'Tashkent');
  assert.equal(listing.district, 'Chilanzar');
  assert.equal(listing.kvartal, '12 kvartal');
  assert.equal(listing.metro, null);
  assert.deepEqual(listing.nearbyShops, ['Havas']);
});

const uchtepaDescription = `Uchtepa tumani 25 dahadan 2 xonali uy ijaraga beriladi, rwmont xolati rasmda bor, faqat oilaga beriladi!
2-qavat / 14-qavatli uy.

Atrofida Bobur bog’i, avtobus kanichkasi, poleklinika, maktab va h.k.z`;

test('parses Uchtepa district, daha, floor pair and nearby amenities', () => {
  const listing = makeListing({
    id: 'uchtepa-test',
    source: 'telegram',
    country: 'UZ',
    title: 'Uchtepa tumani 25 daha',
    description: uchtepaDescription,
  });

  assert.equal(listing.propertyType, 'flat');
  assert.equal(listing.rooms, 2);
  assert.equal(listing.floor, 2);
  assert.equal(listing.totalFloors, 14);
  assert.equal(listing.dealType, 'longRent');
  assert.equal(listing.audience, 'family');
  assert.equal(listing.city, 'Tashkent');
  assert.equal(listing.district, 'Uchtepa');
  assert.equal(listing.kvartal, '25 kvartal');
  assert.deepEqual(listing.nearby, ['Bobur Park', 'Bus stop', 'Clinic', 'School']);
});

test('parses a bare floor / building-height pair', () => {
  assert.deepEqual(parseFloor('Квартира 2 / 14, рядом с парком'), { floor: 2, totalFloors: 14 });
});
