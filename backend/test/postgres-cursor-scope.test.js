import assert from 'node:assert/strict';
import test from 'node:test';

import {
  attachScopeToCursor,
  prepareCursorForScope,
  searchCursorScope,
} from '../src/postgres-cursor-scope.js';

function encodeCursor(value) {
  return Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');
}

function decodeCursor(value) {
  return JSON.parse(Buffer.from(String(value), 'base64url').toString('utf8'));
}

test('cursor scope is stable for equivalent normalized filter sets', () => {
  const first = searchCursorScope({
    city: 'Tashkent',
    sources: ['telegram', 'olx'],
    priceMin: 500,
    limit: 20,
    offset: 40,
    cursor: 'ignored',
    includeStats: false,
  }, ['UZ', 'UA']);
  const second = searchCursorScope({
    includeStats: true,
    offset: 0,
    limit: 60,
    priceMin: 500,
    sources: ['olx', 'telegram'],
    city: 'Tashkent',
  }, ['UA', 'UZ', 'UZ']);

  assert.equal(first, second);
});

test('cursor scope changes with semantic filters or countries', () => {
  const base = searchCursorScope({city: 'Tashkent', sort: 'newest'}, ['UZ']);
  assert.notEqual(base, searchCursorScope({city: 'Samarkand', sort: 'newest'}, ['UZ']));
  assert.notEqual(base, searchCursorScope({city: 'Tashkent', sort: 'newest'}, ['UA']));
  assert.notEqual(base, searchCursorScope({city: 'Tashkent', sort: 'oldest'}, ['UZ']));
});

test('legacy cursor keeps position but loses unscoped carried count', () => {
  const legacy = encodeCursor({
    v: 1,
    sort: 'newest',
    t: '2026-08-30T12:00:00.000Z',
    id: '123',
    c: 999,
  });
  const prepared = prepareCursorForScope(legacy, 'scope-a');
  const parsed = decodeCursor(prepared);

  assert.equal(parsed.id, '123');
  assert.equal(parsed.sort, 'newest');
  assert.equal(parsed.t, '2026-08-30T12:00:00.000Z');
  assert.equal('c' in parsed, false);
  assert.equal('s' in parsed, false);
});

test('scoped cursor is accepted only for its exact query scope', () => {
  const coreCursor = encodeCursor({v: 1, sort: 'newest', t: null, id: '123', c: 7});
  const scoped = attachScopeToCursor(coreCursor, 'scope-a');

  assert.equal(prepareCursorForScope(scoped, 'scope-a'), scoped);
  assert.equal(prepareCursorForScope(scoped, 'scope-b'), '');
  assert.equal(decodeCursor(scoped).s, 'scope-a');
  assert.equal(decodeCursor(scoped).c, 7);
});

test('invalid cursors are rejected instead of reaching SQL builders', () => {
  assert.equal(prepareCursorForScope('not-a-cursor', 'scope-a'), '');
  assert.equal(attachScopeToCursor(null, 'scope-a'), null);
});
