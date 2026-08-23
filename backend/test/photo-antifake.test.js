import test from 'node:test';
import assert from 'node:assert/strict';

import { scoreCloneRelationship } from '../src/photo-antifake.js';

function listing(overrides = {}) {
  return {
    title: 'Assalom Sohil 3/4/10',
    price: 600,
    currency: 'USD',
    byAgency: false,
    rooms: 3,
    areaSqm: 80,
    createdAt: '2026-08-23T08:00:00Z',
    ...overrides,
  };
}

function stored(overrides = {}) {
  return {
    title: 'Assalom Sohil 3/4/10',
    price: 600,
    currency: 'USD',
    by_agency: false,
    rooms: 3,
    area_sqm: 80,
    created_at: '2026-08-23T08:00:00Z',
    ...overrides,
  };
}

test('later materially cheaper copy is suspicious without assuming cheaper always means fraud', () => {
  const result = scoreCloneRelationship(
    listing({ price: 450, createdAt: '2026-08-23T10:00:00Z' }),
    stored({ price: 600, created_at: '2026-08-23T08:00:00Z' }),
  );

  assert.equal(result.currentCopyCandidate, true);
  assert.equal(result.priceDirection, 'lower');
  assert.equal(result.reason, 'possible_low_price_copy');
  assert.ok(result.score >= 70);
});

test('later agency copy with markup is treated as possible broker repost', () => {
  const result = scoreCloneRelationship(
    listing({ price: 780, byAgency: true, createdAt: '2026-08-23T10:00:00Z' }),
    stored({ price: 600, by_agency: false, created_at: '2026-08-23T08:00:00Z' }),
  );

  assert.equal(result.currentCopyCandidate, true);
  assert.equal(result.sellerRelation, 'owner_to_agency');
  assert.equal(result.priceDirection, 'higher');
  assert.equal(result.reason, 'possible_broker_markup_copy');
  assert.ok(result.score >= 70);
});

test('older owner listing is not blamed when a newer agency copy exists', () => {
  const result = scoreCloneRelationship(
    listing({ price: 600, byAgency: false, createdAt: '2026-08-23T08:00:00Z' }),
    stored({ price: 780, by_agency: true, created_at: '2026-08-23T10:00:00Z' }),
  );

  assert.equal(result.currentCopyCandidate, false);
  assert.equal(result.matchedCopyCandidate, true);
  assert.equal(result.reason, 'matched_listing_may_be_copy');
});

test('same-price duplicate remains evidence but not an automatic clone accusation', () => {
  const result = scoreCloneRelationship(
    listing({ createdAt: '2026-08-23T08:05:00Z' }),
    stored({ created_at: '2026-08-23T08:00:00Z' }),
  );

  assert.equal(result.currentCopyCandidate, false);
  assert.equal(result.priceDirection, 'similar');
  assert.equal(result.reason, 'duplicate_listing');
  assert.ok(result.score < 70);
});
