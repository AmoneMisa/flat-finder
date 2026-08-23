import test from 'node:test';
import assert from 'node:assert/strict';
import {readdirSync, readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const srcRoot = fileURLToPath(new URL('../src/', import.meta.url));

function jsFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir, {withFileTypes: true})) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...jsFiles(full));
    else if (entry.isFile() && entry.name.endsWith('.js')) out.push(full);
  }
  return out;
}

function relative(file) {
  return path.relative(srcRoot, file).replaceAll('\\', '/');
}

function consumersOf(pattern, excluded = []) {
  const consumers = [];
  for (const file of jsFiles(srcRoot)) {
    if (excluded.includes(relative(file))) continue;
    const source = readFileSync(file, 'utf8');
    if (pattern.test(source)) consumers.push(relative(file));
  }
  return consumers;
}

test('retired legacy scraper registry stays absent from runtime imports', () => {
  assert.deepEqual(consumersOf(/scrapers\/index\.js/), []);
});

test('HTTP route modules never import custom scraper execution helpers', () => {
  for (const name of ['listing-routes.js', 'listing-item-routes.js', 'app.js', 'server.js']) {
    const source = readFileSync(path.join(srcRoot, name), 'utf8');
    assert.doesNotMatch(source, /scrapers\/custom\.js/, `${name} must not execute custom fetches`);
    assert.doesNotMatch(source, /\bvalidateSource\b/, `${name} must use the queue adapter`);
    assert.doesNotMatch(source, /\bscrapeCustom\b/, `${name} must use the queue adapter`);
  }
});
