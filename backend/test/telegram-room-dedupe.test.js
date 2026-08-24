import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

import {makeListing} from '../src/normalize.js';
import {looksTelegramRoomShare} from '../src/telegram-room-share.js';

const postgresSearch = await readFile(new URL('../src/postgres-search.js', import.meta.url), 'utf8');
const telegramScraper = await readFile(new URL('../src/scrapers/telegram.js', import.meta.url), 'utf8');

test('recognizes Uzbek place-in-flat offers without treating audience alone as room-only', () => {
  assert.equal(looksTelegramRoomShare('Kvartira ijarasi. Qizlarga joy bor. Novza metro.'), true);
  assert.equal(looksTelegramRoomShare('Kvartira ijarasi. Qizlar uchun joy mavjud.'), true);
  assert.equal(looksTelegramRoomShare('Квартира ижара. Қизларга жой бор.'), true);
  assert.equal(looksTelegramRoomShare('Сдается квартира, только для девушек.'), false);
  assert.equal(looksTelegramRoomShare('Kvartira faqat qizlarga beriladi.'), false);
});

test('Telegram scraper forwards colloquial share detection into normalized roomOnly', () => {
  assert.match(telegramScraper, /import \{looksTelegramRoomShare\} from '\.\.\/telegram-room-share\.js'/);
  assert.match(
    telegramScraper,
    /roomOnly:\s*looksTelegramRoomShare\(text\)(?:\s*\?\s*true\s*:\s*undefined)?/,
  );
});

test('single-photo Telegram reposts require matching structured listing fields', () => {
  const fingerprint = 'a'.repeat(64);
  const base = {
    source: 'telegram',
    country: 'UZ',
    title: 'Kvartira Ijarasi | Maklersiz ✅',
    description: 'Same apartment repost with slightly different trailing text',
    propertyType: 'flat',
    dealType: 'longRent',
    price: 100,
    currency: 'USD',
    rooms: 3,
    city: 'Tashkent',
    photoFingerprints: [fingerprint],
  };

  const first = makeListing({...base, id: 'one'});
  const repost = makeListing({...base, id: 'two', description: 'Text can differ while structured identity stays the same'});
  const differentPrice = makeListing({...base, id: 'three', price: 150});

  assert.equal(first.photoFingerprintKey?.length, 129);
  assert.equal(first.photoFingerprintKey, repost.photoFingerprintKey);
  assert.notEqual(first.photoFingerprintKey, differentPrice.photoFingerprintKey);
});

test('Telegram scraper canonicalizes multi-photo fingerprints without using photo ids as a semantic key', () => {
  assert.match(telegramScraper, /msg\.photoFingerprints/);
  assert.match(telegramScraper, /photoFingerprints\.join\('\|'\)/);
});

test('PostgreSQL feed consumes photo fingerprint keys, falls back to content, and keeps exact-id lookup', () => {
  assert.match(postgresSearch, /'telegram:photos:' \|\| MD5/);
  assert.match(postgresSearch, /data->>'photoFingerprintKey'/);
  assert.match(postgresSearch, /LENGTH\(\$\{telegramPhotoKey\}\) >= 129/);
  assert.match(postgresSearch, /'telegram:content:' \|\| MD5/);
  assert.match(postgresSearch, /LENGTH\(\$\{description\}\) >= 40/);
  assert.match(postgresSearch, /const dedupeEnabled = !filters\.listingId/);
});
