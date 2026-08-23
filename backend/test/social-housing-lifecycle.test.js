import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const scraper = readFileSync(new URL('../src/scrapers/social.js', import.meta.url), 'utf8');
const scheduler = readFileSync(new URL('../src/social-housing-scheduler.js', import.meta.url), 'utf8');

test('partial social target crawls do not report a complete source crawl', () => {
  assert.match(scraper, /const errors = \[\]/);
  assert.match(scraper, /complete: errors\.length === 0/);
  assert.match(scraper, /partialExpected: errors\.length > 0/);
});

test('complete social crawls age out missing rows and sync ES deactivation', () => {
  assert.match(scheduler, /markMissingAfterCompleteCrawl/);
  assert.match(scheduler, /result\?\.complete === true/);
  assert.match(scheduler, /deleteListingDocuments\(missing\.deactivated\)/);
  assert.match(scheduler, /crawlStartedAt/);
});
