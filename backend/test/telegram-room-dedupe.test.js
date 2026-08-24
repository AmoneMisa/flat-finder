import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

import {looksTelegramRoomShare} from '../src/telegram-room-share.js';

const postgresSearch = await readFile(new URL('../src/postgres-search.js', import.meta.url), 'utf8');
const telegramScraper = await readFile(new URL('../src/scrapers/telegram.js', import.meta.url), 'utf8');
const normalize = await readFile(new URL('../src/normalize.js', import.meta.url), 'utf8');

test('recognizes Uzbek place-in-flat offers without treating audience alone as room-only', () => {
  assert.equal(looksTelegramRoomShare('Kvartira ijarasi. Qizlarga joy bor. Novza metro.'), true);
  assert.equal(looksTelegramRoomShare('Kvartira ijarasi. Qizlar uchun joy mavjud.'), true);
  assert.equal(looksTelegramRoomShare('Квартира ижара. Қизларга жой бор.'), true);
  assert.equal(looksTelegramRoomShare('Сдается квартира, только для девушек.'), false);
  assert.equal(looksTelegramRoomShare('Kvartira faqat qizlarga beriladi.'), false);
});

test('Telegram scraper forwards colloquial share detection into normalized roomOnly', () => {
  assert.match(telegramScraper, /import \{looksTelegramRoomShare\} from '\.\.\/telegram-room-share\.js'/);
  assert.match(telegramScraper, /roomOnly:\s*\n\s*looksTelegramRoomShare\(text\)/);
});

test('Telegram scraper canonicalizes photo fingerprints without using photo ids as a semantic key', () => {
  assert.match(telegramScraper, /msg\.photoFingerprints/);
  assert.match(telegramScraper, /photoFingerprints\.join\('\|'\)/);
  assert.match(telegramScraper, /photoFingerprints\.length >= 2/);
  assert.match(normalize, /photoFingerprintKey: partial\.photoFingerprintKey \?\? null/);
});

test('PostgreSQL feed prefers two-photo fingerprint dedupe, falls back to content, and keeps exact-id lookup', () => {
  assert.match(postgresSearch, /'telegram:photos:' \|\| MD5/);
  assert.match(postgresSearch, /data->>'photoFingerprintKey'/);
  assert.match(postgresSearch, /LENGTH\(\$\{telegramPhotoKey\}\) >= 129/);
  assert.match(postgresSearch, /'telegram:content:' \|\| MD5/);
  assert.match(postgresSearch, /LENGTH\(\$\{description\}\) >= 40/);
  assert.match(postgresSearch, /const dedupeEnabled = !filters\.listingId/);
});
