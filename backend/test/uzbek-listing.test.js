import test from 'node:test';
import assert from 'node:assert/strict';

import { applyFilters, makeListing } from '../src/normalize.js';
import { classifyAgency, parseContact, parseDeposit, parseFloor, parsePriceFromText } from '../src/textparse.js';

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

test('parses compact room, floor, area and named orientation from a Telegram post', () => {
  const text = `Сдается квартира

Яккасарайский район "ЖК Kislorod"

Ориентир: Seoul Mun

2/5/16 56кв

Цена: 350$

Пишите / звоните:

771443473 tel`;
  const listing = makeListing({
    id: 'kislorod-test',
    source: 'telegram',
    country: 'UZ',
    title: 'Сдается квартира',
    description: text,
    price: 350,
    currency: 'USD',
  });

  assert.equal(listing.dealType, 'longRent');
  assert.equal(listing.propertyType, 'flat');
  assert.equal(listing.city, 'Tashkent');
  assert.equal(listing.district, 'Yakkasaray');
  assert.equal(listing.residenceComplex, 'Kislorod');
  assert.deepEqual(listing.nearby, ['Seoul Mun']);
  assert.equal(listing.rooms, 2);
  assert.equal(listing.floor, 5);
  assert.equal(listing.totalFloors, 16);
  assert.equal(listing.areaSqm, 56);
  assert.equal(listing.price, 350);
  assert.equal(listing.currency, 'USD');
  assert.equal(listing.contact, '771443473');
  assert.equal(parseContact(text), '771443473');
});

test('parses a basement rental and keeps its labelled base price', () => {
  const text = `🔥 СРОЧНО! АРЕНДА КВАРТИРЫ 🔥

📍 Учтепа Авеню
🏠 2/0/-1 этаж (подвал)
💰 Аренда: 400$
👨‍👩‍👧 Для семьи — 450$
👶 Для семьи с 4 детьми — 400$`;

  const parsedPrice = parsePriceFromText(text, 'UZS');
  const listing = makeListing({
    id: 'uchtepa-basement-test',
    source: 'telegram',
    country: 'UZ',
    title: '🔥 СРОЧНО! АРЕНДА КВАРТИРЫ 🔥',
    description: text,
    price: parsedPrice.price,
    currency: parsedPrice.currency,
  });

  assert.equal(listing.rooms, 2);
  assert.equal(listing.floor, -1);
  assert.equal(listing.totalFloors, null);
  assert.equal(listing.price, 400);
  assert.equal(listing.currency, 'USD');
  assert.equal(listing.dealType, 'longRent');
  assert.equal(listing.district, 'Uchtepa');
});

test('parses hashtag complex, utilities and transit from a Yashnobod post', () => {
  const text = `😉😉😚😉😚
#Яшнабадский
#1комнатная
#ЖКАссаломСохил
Ориентир Узбум

1 комнатная
9 этаж
9 этажный дом

Цена 5 миллионов
Коммунальные услуги отдельно.

Сдается квартира в новостройке,возле центра города.
До метро Ташкент Северный вокзал 5 минут на машине.
Заселяют семейную пару и одиночек мужчину или женщину.

+998903720270 @arenda_tashkent10`;
  const parsedPrice = parsePriceFromText(text, 'UZS');
  const listing = makeListing({
    id: 'yashnobod-assalom-test',
    source: 'telegram',
    country: 'UZ',
    title: '😉😉😚😉😚',
    description: text,
    price: parsedPrice.price,
    currency: parsedPrice.currency,
  });

  assert.equal(listing.dealType, 'longRent');
  assert.equal(listing.rooms, 1);
  assert.equal(listing.floor, 9);
  assert.equal(listing.totalFloors, 9);
  assert.equal(listing.price, 5_000_000);
  assert.equal(listing.currency, 'UZS');
  assert.equal(listing.city, 'Tashkent');
  assert.equal(listing.district, 'Yashnobod');
  assert.equal(listing.residenceComplex, 'Ассалом Сохил');
  assert.equal(listing.metro, 'Tashkent North Railway Station');
  assert.deepEqual(listing.nearby, ['Узбум']);
  assert.equal(listing.newBuilding, true);
  assert.equal(listing.communalSeparated, true);
  assert.equal(listing.audience, null);
  assert.equal(listing.contact, '+998903720270');
});

test('infers Tashkent from Alay and puts dishwasher into other amenities', () => {
  const text = `#4комнатная #Ц2 #Алайский #Центр

Сдается хорошая, комфортная квартира в центре города. Отличная локация, рядом метро, школы.
Имеется вся техника для жизни, в том числе посудомойка.

Комнаты раздельные.
Цена - 850$ Предоплаты нет, депозит обсуждается на месте.

+998903720270 @arenda_tashkent10`;
  const parsedPrice = parsePriceFromText(text, 'UZS');
  const listing = makeListing({
    id: 'alay-c2-test',
    source: 'telegram',
    country: 'UZ',
    title: '#4комнатная #Ц2 #Алайский #Центр',
    description: text,
    price: parsedPrice.price,
    currency: parsedPrice.currency,
  });

  assert.equal(listing.city, 'Tashkent');
  assert.equal(listing.rooms, 4);
  assert.equal(listing.kvartal, 'C-2');
  assert.equal(listing.price, 850);
  assert.equal(listing.currency, 'USD');
  assert.deepEqual(listing.nearby, ['Alay Bazaar', 'C-2', 'School']);
  assert.deepEqual(listing.amenities, ['Dishwasher', 'Separate rooms']);
});

test('recognizes first-person long rent and all nearby place categories', () => {
  const text = `Сдаю чистую квартиру порядочным людям. В квартире есть все необходимые бытовые техники также рядом есть школа, ТЦ, поликлиника, мечеть и т.д.

Шторы повесим позже

Если не отвечу на звонок пиш

993758330 tel`;
  const listing = makeListing({
    id: 'nearby-categories-test',
    source: 'telegram',
    country: 'UZ',
    title: 'Сдаю чистую квартиру порядочным людям',
    description: text,
  });

  assert.equal(listing.dealType, 'longRent');
  assert.deepEqual(listing.nearby, ['Clinic', 'School', 'Shopping center', 'Mosque']);
  assert.equal(listing.contact, '993758330');
});

test('parses Uzbek Cyrillic rooms, locative floor and implicit monthly rent', () => {
  const text = '2 хонали 3 этажда ремонти яхши холатда турибди 350$';
  const parsedPrice = parsePriceFromText(text, 'UZS');
  const listing = makeListing({
    id: 'uzbek-cyrillic-floor-test',
    source: 'telegram',
    country: 'UZ',
    title: text,
    description: text,
    price: parsedPrice.price,
    currency: parsedPrice.currency,
  });

  assert.equal(listing.rooms, 2);
  assert.equal(listing.floor, 3);
  assert.equal(listing.totalFloors, null);
  assert.equal(listing.price, 350);
  assert.equal(listing.currency, 'USD');
  assert.equal(listing.dealType, 'longRent');
});

test('infers Tashkent from Darkhan and Novomoskovskaya landmarks', () => {
  const text = `#2комнатная #Новомосковская

2 комнатная
1 этаж
2 этажного дом

Сдается 2 комнатная квартира в центре города, ориентир: Дархан, Новомосковская.
Для семьи без детей, можно двум девушкам или маме с детьми!

Цена 450$

+998903720270 @arenda_tashkent10`;
  const parsedPrice = parsePriceFromText(text, 'UZS');
  const listing = makeListing({
    id: 'darkhan-novomoskovskaya-test',
    source: 'telegram',
    country: 'UZ',
    title: '#2комнатная #Новомосковская',
    description: text,
    price: parsedPrice.price,
    currency: parsedPrice.currency,
  });

  assert.equal(listing.city, 'Tashkent');
  assert.equal(listing.rooms, 2);
  assert.equal(listing.floor, 1);
  assert.equal(listing.totalFloors, 2);
  assert.equal(listing.dealType, 'longRent');
  assert.equal(listing.price, 450);
  assert.equal(listing.currency, 'USD');
  assert.deepEqual(listing.nearby, ['Darkhan', 'Novomoskovskaya']);
});

test('does not use a following phone number as the deposit amount', () => {
  const text = `Цена 450$\n\nИмеется договорной депозит.\n\n+998903720270 @arenda_tashkent10`;
  assert.deepEqual(parseDeposit(text), { required: true, amount: null });
  assert.deepEqual(parseDeposit('Залог 500$; телефон +998 90 123 45 67'), { required: true, amount: 500 });
  assert.deepEqual(parseDeposit('Депозит 1 500 000 UZS'), { required: true, amount: 1_500_000 });
});

test('finds one shared listing by exact id outside normal pagination', () => {
  const rows = [
    { id: 'first', source: 'telegram', commercial: false },
    { id: 'shared-row', source: 'telegram', commercial: false },
  ];
  assert.deepEqual(
    applyFilters(rows, { listingId: 'shared-row', sources: ['telegram'] }).map(({ id }) => id),
    ['shared-row'],
  );
});
