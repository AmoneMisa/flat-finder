import test from 'node:test';
import assert from 'node:assert/strict';

import { COUNTRIES } from '../src/countries.js';
import { ownerHousingSources } from '../src/owner-housing-sources.js';
import { realtorHousingSources } from '../src/realtor-housing-sources.js';
import { telegramHousingChannels } from '../src/telegram-housing-sources.js';
import { buildCrawlPlan } from '../src/queuePlan.js';
import { enforceOwnerOnlyListings } from '../src/queueTasks.js';

test('owner registry covers the curated direct-owner platforms', () => {
  const urls = Object.keys(COUNTRIES).flatMap((country) => ownerHousingSources(country).map((source) => source.url));
  for (const expected of [
    'https://rentli.uz/en/listings',
    'https://ostona.app/en',
    'https://easy-house.in.ua/search/',
    'https://www.proprietaripebune.ro/chirii/bucuresti',
    'https://arendator.kg/',
  ]) {
    assert.equal(urls.filter((url) => url === expected).length, 1, expected);
  }
  assert.ok(!realtorHousingSources('UZ').some((source) => source.url.includes('rentli.uz')));
  assert.equal(COUNTRIES.KG?.currency, 'KGS');
});

test('owner Telegram overrides replace older bare channel entries', () => {
  const uz = telegramHousingChannels('UZ', COUNTRIES.UZ.telegramChannels);
  const arentash = uz.find((channel) => typeof channel === 'object' && channel.name === 'arentash');
  assert.equal(arentash?.ownerOnly, true);
  assert.deepEqual(arentash?.ownerMarkers, ['#хозяева']);
  assert.deepEqual(arentash?.ownerRejectMarkers, ['#риелтор']);

  const kz = telegramHousingChannels('KZ', COUNTRIES.KZ.telegramChannels);
  assert.equal(kz.find((channel) => channel?.name === 'kvartiry2')?.ownerOnly, true);
  assert.equal(kz.find((channel) => channel?.name === 'freehomekz_Almaty')?.dealType, 'shortRent');

  const ua = telegramHousingChannels('UA', COUNTRIES.UA.telegramChannels);
  assert.equal(ua.find((channel) => channel?.name === 'kievrentfree')?.ownerOnly, true);
  assert.equal(ua.find((channel) => channel?.name === 'orenda_bez_rieltora')?.ownerOnly, true);
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
    'easyhouse-ukraine-owner-rent',
    'proprietari-pe-bune-bucharest-owner-rent',
    'arendator-bishkek-owner-rent',
  ]) {
    assert.ok(tasks.some((task) => task.type === 'flat.custom.url' && task.segment === segment && task.ownerOnly));
  }
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
