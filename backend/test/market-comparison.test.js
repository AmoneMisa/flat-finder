import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const comparison = await readFile(new URL('../src/market-comparison.js', import.meta.url), 'utf8');
const routes = await readFile(new URL('../src/listing-routes.js', import.meta.url), 'utf8');
const migration = await readFile(new URL('../migrations/009_market_comparison_indexes.sql', import.meta.url), 'utf8');

test('good-price assessment is calculated from the active PostgreSQL market, not the loaded page', () => {
  assert.match(routes, /attachMarketComparisons\(listings, fxRates\)/u);
  assert.match(comparison, /JOIN listings c/u);
  assert.match(comparison, /c\.active = TRUE/u);
  assert.match(comparison, /PERCENTILE_CONT\(0\.5\) WITHIN GROUP \(ORDER BY price_usd\)/u);
  assert.match(comparison, /stats\.comparableCount >= MIN_COMPARABLES/u);
  assert.match(comparison, /target\.price_usd < stats\.medianUsd/u);
});

test('market comparison matches city, district, deal, property type and rooms with an area fallback', () => {
  assert.match(comparison, /UPPER\(c\.country\) = t\.country/u);
  assert.match(comparison, /LOWER\(BTRIM\(COALESCE\(c\.city, ''\)\)\) = LOWER\(BTRIM\(t\.city\)\)/u);
  assert.match(comparison, /t\.district IS NULL OR LOWER\(BTRIM\(COALESCE\(c\.district, ''\)\)\) = LOWER\(BTRIM\(t\.district\)\)/u);
  assert.match(comparison, /c\.property_type = t\.property_type/u);
  assert.match(comparison, /roomOnly/u);
  assert.match(comparison, /t\.rooms IS NOT NULL AND c\.rooms = t\.rooms/u);
  assert.match(comparison, /GREATEST\(5\.0, t\.area_sqm \* 0\.15\)/u);
});

test('market median uses the same source-level duplicate suppression and has lookup indexes', () => {
  assert.match(comparison, /SELECT DISTINCT ON \(key, dedupe_key\)/u);
  assert.match(comparison, /telegram:photos/u);
  assert.match(comparison, /olx:photos/u);
  assert.match(migration, /listings_market_rooms_idx/u);
  assert.match(migration, /listings_market_area_idx/u);
});
