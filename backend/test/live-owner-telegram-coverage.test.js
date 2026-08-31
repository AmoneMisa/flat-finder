import test from 'node:test';
import assert from 'node:assert/strict';

import { COUNTRIES } from '../src/countries.js';
import { telegramHousingChannels } from '../src/telegram-housing-sources.js';
import { buildCrawlPlan } from '../src/queuePlan.js';

test('Ukraine live owner feeds are queued with strict owner semantics', () => {
  const channels = telegramHousingChannels('UA', COUNTRIES.UA.telegramChannels);
  const byName = (name) => channels.find((channel) => channel?.name === name);

  assert.equal(byName('direct_rent')?.city, 'Lviv');
  assert.equal(byName('direct_rent')?.ownerOnly, true);
  assert.equal(byName('direct_rent')?.dealType, 'longRent');

  assert.equal(byName('direct_rent_cv')?.ownerOnly, true);
  assert.equal(byName('direct_rent_cv')?.city, 'Chernivtsi');
  assert.equal(byName('direct_rent_rivne')?.ownerOnly, true);
  assert.equal(byName('direct_rent_rivne')?.city, 'Rivne');

  assert.equal(byName('lviv_no_maklers')?.ownerOnly, true);
  assert.ok(byName('lviv_no_maklers')?.ownerMarkers.includes('#власник'));

  assert.equal(byName('rent_frankivsk')?.ownerOnly, true);
  assert.ok(byName('rent_frankivsk')?.ownerMarkers.includes('#власник'));

  assert.equal(byName('SMARTIN_MYKOLAYIV')?.ownerOnly, true);
  assert.ok(byName('SMARTIN_MYKOLAYIV')?.ownerMarkers.includes('від власника'));

  assert.equal(byName('rentin_khmelnytskyi')?.ownerOnly, true);
  assert.ok(byName('rentin_khmelnytskyi')?.ownerMarkers.includes('без комісії ріелтора'));

  const { tasks } = buildCrawlPlan({ shardCount: 2 });
  for (const name of [
    'direct_rent',
    'direct_rent_cv',
    'direct_rent_rivne',
    'lviv_no_maklers',
    'rent_frankivsk',
    'SMARTIN_MYKOLAYIV',
    'rentin_khmelnytskyi',
  ]) {
    assert.ok(tasks.some((task) =>
      task.type === 'flat.telegram.channel'
      && task.country === 'UA'
      && task.channel === name
      && task.ownerOnly === true,
    ), name);
  }
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
