import test from 'node:test';
import assert from 'node:assert/strict';

import { COUNTRIES } from '../src/countries.js';
import { ownerHousingSources } from '../src/owner-housing-sources.js';
import { realtorHousingSources } from '../src/realtor-housing-sources.js';
import { telegramHousingChannels } from '../src/telegram-housing-sources.js';
import { buildCrawlPlan } from '../src/queuePlan.js';
import { enforceOwnerOnlyListings } from '../src/queueTasks.js';

test('owner registry covers curated direct-owner platforms in every configured country', () => {
  const urls = Object.keys(COUNTRIES).flatMap((country) => ownerHousingSources(country).map((source) => source.url));
  for (const expected of [
    'https://rentli.uz/en/listings',
    'https://ostona.app/en',
    'https://turar.uz/ru/tashkent',
    'https://easy-house.in.ua/search/',
    'https://kvarto.app/uk',
    'https://www.kn.kz/almaty/arenda-kvartir-bez-posrednikov-s-foto',
    'https://www.proprietaripebune.ro/chirii/bucuresti',
    'https://proprietar-direct.ro/categorii-anunturi/oferte-de-inchiriat/',
    'https://arendator.kg/',
    'https://sutochno.kg/bishkek/',
  ]) {
    assert.equal(urls.filter((url) => url === expected).length, 1, expected);
  }
  assert.equal(ownerHousingSources('UZ').find((source) => source.key === 'turar-tashkent-owner-daily')?.dealType, 'shortRent');
  assert.equal(ownerHousingSources('KG').find((source) => source.key === 'sutochno-bishkek-owner-daily')?.dealType, 'shortRent');
  assert.ok(!realtorHousingSources('UZ').some((source) => source.url.includes('rentli.uz')));
  assert.equal(COUNTRIES.KG?.currency, 'KGS');
  assert.deepEqual(COUNTRIES.KG?.sources, ['telegram']);
});

test('owner Telegram overrides replace older bare channel entries', () => {
  const uz = telegramHousingChannels('UZ', COUNTRIES.UZ.telegramChannels);
  const arentash = uz.find((channel) => typeof channel === 'object' && channel.name === 'arentash');
  assert.equal(arentash?.ownerOnly, true);
  assert.deepEqual(arentash?.ownerMarkers, ['#хозяева']);
  assert.deepEqual(arentash?.ownerRejectMarkers, ['#риелтор']);
  assert.equal(uz.find((channel) => channel?.name === 'ijaraga_kvartiralar_Bezmakler')?.ownerOnly, true);

  const kz = telegramHousingChannels('KZ', COUNTRIES.KZ.telegramChannels);
  assert.equal(kz.find((channel) => channel?.name === 'kvartiry2')?.ownerOnly, true);
  assert.equal(kz.find((channel) => channel?.name === 'freehomekz_Almaty')?.dealType, 'shortRent');

  const ua = telegramHousingChannels('UA', COUNTRIES.UA.telegramChannels);
  assert.equal(ua.find((channel) => channel?.name === 'kievrentfree')?.ownerOnly, true);
  assert.equal(ua.find((channel) => channel?.name === 'orenda_bez_rieltora')?.ownerOnly, true);
  assert.equal(ua.find((channel) => channel?.name === 'orenda_kyiv_city')?.ownerOnly, true);
  assert.equal(ua.find((channel) => channel?.name === 'arendakyiv_ua')?.ownerOnly, true);

  const kg = telegramHousingChannels('KG', COUNTRIES.KG.telegramChannels);
  const bishkek = kg.find((channel) => channel?.name === 'bishkekarendakv');
  assert.equal(bishkek?.ownerOnly, true);
  assert.equal(bishkek?.dealType, 'longRent');
  assert.ok(bishkek?.ownerMarkers.includes('от собственника'));
});

test('crawl plan restores daily OLX and queues owner-first sources', () => {
  const { tasks } = buildCrawlPlan({ shardCount: 2 });
  for (const country of ['UZ', 'KZ', 'UA', 'RO']) {
    assert.ok(tasks.some((task) => task.type === 'flat.olx.page' && task.country === country && task.segment === 'flat:shortRent'));
  }
  const roLongRent = tasks.find((task) => task.type === 'flat.olx.page' && task.country === 'RO' && task.segment === 'flat:longRent');
  assert.equal(roLongRent?.ownerOnly, true);
  for (const segment of [
    'rentli-tashkent-owner-rent',
    'turar-tashkent-owner-daily',
    'easyhouse-ukraine-owner-rent',
    'kvarto-ukraine-owner-rent',
    'kn-almaty-owner-rent',
    'proprietari-pe-bune-bucharest-owner-rent',
    'proprietar-direct-romania-owner-rent',
    'arendator-bishkek-owner-rent',
    'sutochno-bishkek-owner-daily',
  ]) {
    assert.ok(tasks.some((task) => task.type === 'flat.custom.url' && task.segment === segment && task.ownerOnly));
  }
  assert.ok(tasks.some((task) =>
    task.type === 'flat.telegram.channel'
    && task.country === 'KG'
    && task.channel === 'bishkekarendakv'
    && task.ownerOnly,
  ));
});

test('owner policy rejects realtor-marked inventory', () => {
  const listings = [
    { title: 'Сдаю квартиру', description: 'Ташкент 2 комнаты 500$ #хозяева', byAgency: false },
    { title: 'Сдаю квартиру', description: 'Ташкент 2 комнаты 500$ #риелтор', byAgency: false },
    { title: 'Сдам квартиру', description: 'Комиссия риелтора 50%, Ташкент', byAgency: true },
  ];
  const filtered = enforceOwnerOnlyListings(listings, {
    ownerOnly: true,
    ownerMarkers: ['#хозяева'],
    ownerRejectMarkers: ['#риелтор'],
    dealType: 'longRent',
  });
  assert.equal(filtered.length, 1);
  assert.equal(filtered[0].byAgency, false);
  assert.equal(filtered[0].commission, false);
  assert.equal(filtered[0].commissionPercent, 0);
  assert.equal(filtered[0].dealType, 'longRent');
});
