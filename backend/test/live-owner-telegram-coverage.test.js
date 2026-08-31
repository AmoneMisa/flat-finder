import test from 'node:test';
import assert from 'node:assert/strict';

import { COUNTRIES } from '../src/countries.js';
import { telegramHousingChannels } from '../src/telegram-housing-sources.js';
import { buildCrawlPlan } from '../src/queuePlan.js';

test('Ukraine keeps dedicated owner feeds without suppressing mixed channels', () => {
  const channels = telegramHousingChannels('UA', COUNTRIES.UA.telegramChannels);
  const byName = (name) => channels.find((channel) => channel?.name === name);

  for (const [name, city] of [
    ['direct_rent', 'Lviv'],
    ['direct_rent_cv', 'Chernivtsi'],
    ['direct_rent_rivne', 'Rivne'],
    ['lviv_no_maklers', 'Lviv'],
    ['BEZ_rieltoriv_DP', 'Dnipro'],
    ['LUTSK_ORENDA', 'Lutsk'],
    ['Ternopol_arenda', 'Ternopil'],
  ]) {
    assert.equal(byName(name)?.city, city, name);
    assert.equal(byName(name)?.ownerOnly, true, name);
  }

  // Mixed feeds must stay mixed so owner and realtor listings remain visible.
  for (const name of ['KH_Rent', 'rent_frankivsk', 'SMARTIN_MYKOLAYIV', 'rentin_khmelnytskyi']) {
    assert.notEqual(byName(name)?.ownerOnly, true, name);
  }

  const { tasks } = buildCrawlPlan({ shardCount: 2 });
  for (const name of [
    'direct_rent',
    'direct_rent_cv',
    'direct_rent_rivne',
    'lviv_no_maklers',
    'BEZ_rieltoriv_DP',
    'LUTSK_ORENDA',
    'Ternopol_arenda',
  ]) {
    assert.ok(tasks.some((task) =>
      task.type === 'flat.telegram.channel'
      && task.country === 'UA'
      && task.channel === name
      && task.ownerOnly === true,
    ), name);
  }

  for (const name of ['KH_Rent', 'rent_frankivsk', 'SMARTIN_MYKOLAYIV', 'rentin_khmelnytskyi']) {
    assert.ok(tasks.some((task) =>
      task.type === 'flat.telegram.channel'
      && task.country === 'UA'
      && task.channel === name
      && task.ownerOnly !== true,
    ), name);
  }
});

test('Kazakhstan adds Astana owner and mixed feeds side by side', () => {
  const channels = telegramHousingChannels('KZ', COUNTRIES.KZ.telegramChannels);
  const byName = (name) => channels.find((channel) => channel?.name === name);

  assert.equal(byName('arenda_kvartiry_astana')?.ownerOnly, true);
  assert.equal(byName('arenda_kvartiry_astana')?.city, 'Astana');
  assert.notEqual(byName('rentinastana')?.ownerOnly, true);
  assert.equal(byName('rentinastana')?.city, 'Astana');
  assert.notEqual(byName('kvartira_v_almaty')?.ownerOnly, true);

  const { tasks } = buildCrawlPlan({ shardCount: 2 });
  assert.ok(tasks.some((task) =>
    task.type === 'flat.telegram.channel'
    && task.country === 'KZ'
    && task.channel === 'arenda_kvartiry_astana'
    && task.ownerOnly === true,
  ));
  assert.ok(tasks.some((task) =>
    task.type === 'flat.telegram.channel'
    && task.country === 'KZ'
    && task.channel === 'rentinastana'
    && task.ownerOnly !== true,
  ));
});

test('mixed Bishkek and Tashkent feeds are not narrowed to owners only', () => {
  const kg = telegramHousingChannels('KG', COUNTRIES.KG.telegramChannels);
  const bishkek = kg.find((channel) => channel?.name === 'bishkekarendakv');
  assert.equal(bishkek?.city, 'Bishkek');
  assert.notEqual(bishkek?.ownerOnly, true);

  const uz = telegramHousingChannels('UZ', COUNTRIES.UZ.telegramChannels);
  assert.ok(uz.some((channel) => channel === 'arentash'));
  assert.ok(!uz.some((channel) => channel?.name === 'arentash' && channel.ownerOnly === true));
});

test('Tashkent live daily feed is owner-only short rent', () => {
  const channels = telegramHousingChannels('UZ', COUNTRIES.UZ.telegramChannels);
  const daily = channels.find((channel) => channel?.name === 'kunlik_kvartira_1');

  assert.equal(daily?.city, 'Tashkent');
  assert.equal(daily?.dealType, 'shortRent');
  assert.equal(daily?.ownerOnly, true);
  assert.ok(daily?.ownerMarkers.includes('egasi'));
  assert.ok(daily?.ownerMarkers.includes('bezmakler'));

  const { tasks } = buildCrawlPlan({ shardCount: 2 });
  assert.ok(tasks.some((task) =>
    task.type === 'flat.telegram.channel'
    && task.country === 'UZ'
    && task.channel === 'kunlik_kvartira_1'
    && task.ownerOnly === true,
  ));
});
